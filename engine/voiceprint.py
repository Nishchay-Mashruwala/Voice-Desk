"""Speaker verification ("is this the user's voice?") without torch.

Uses the Wespeaker ResNet34 ONNX model (26 MB, not gated) on onnxruntime,
with Kaldi-compatible filterbank features computed in numpy. Loading it costs
~60 MB of RAM, versus ~700 MB for torch + pyannote.
"""

from __future__ import annotations

import functools

import numpy as np

SAMPLE_RATE = 16000
REPO = "Wespeaker/wespeaker-voxceleb-resnet34-LM"
FILENAME = "voxceleb_resnet34_LM.onnx"

_FRAME_LEN = 400  # 25 ms
_FRAME_SHIFT = 160  # 10 ms
_NFFT = 512
_NUM_MELS = 80


@functools.lru_cache(maxsize=1)
def _mel_banks() -> np.ndarray:
    """Kaldi-style triangular mel filters: (num_mels, nfft/2) over 20 Hz – Nyquist."""

    def mel(f: np.ndarray | float) -> np.ndarray:
        return 1127.0 * np.log(1.0 + np.asarray(f) / 700.0)

    num_bins = _NFFT // 2
    fft_bin_width = SAMPLE_RATE / _NFFT
    low, high = mel(20.0), mel(SAMPLE_RATE / 2)
    delta = (high - low) / (_NUM_MELS + 1)
    bin_mels = mel(fft_bin_width * np.arange(num_bins))
    banks = np.zeros((_NUM_MELS, num_bins), dtype=np.float64)
    for m in range(_NUM_MELS):
        left, center, right = low + m * delta, low + (m + 1) * delta, low + (m + 2) * delta
        up = (bin_mels - left) / (center - left)
        down = (right - bin_mels) / (right - center)
        banks[m] = np.maximum(0.0, np.minimum(up, down))
    return banks


def fbank(audio: np.ndarray) -> np.ndarray:
    """80-dim log-mel filterbank matching torchaudio.compliance.kaldi.fbank
    (hamming window, dither 0, snip_edges, no energy) on int16-scaled audio."""
    x = audio.astype(np.float64) * 32768.0
    if len(x) < _FRAME_LEN:
        x = np.pad(x, (0, _FRAME_LEN - len(x)))
    n_frames = 1 + (len(x) - _FRAME_LEN) // _FRAME_SHIFT
    idx = np.arange(_FRAME_LEN)[None, :] + _FRAME_SHIFT * np.arange(n_frames)[:, None]
    frames = x[idx]
    frames = frames - frames.mean(axis=1, keepdims=True)  # remove DC offset
    # Pre-emphasis (Kaldi replicates the first sample).
    prev = np.concatenate([frames[:, :1], frames[:, :-1]], axis=1)
    frames = frames - 0.97 * prev
    frames = frames * np.hamming(_FRAME_LEN)
    spec = np.abs(np.fft.rfft(frames, n=_NFFT)) ** 2
    mel = spec[:, : _NFFT // 2] @ _mel_banks().T
    eps = np.finfo(np.float32).eps
    return np.log(np.maximum(mel, eps)).astype(np.float32)


class VoicePrint:
    def __init__(self) -> None:
        self.session = None

    def load(self) -> None:
        if self.session is not None:
            return
        import onnxruntime as ort
        from huggingface_hub import hf_hub_download

        path = hf_hub_download(REPO, FILENAME)
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 2  # verification is tiny; don't compete with Whisper
        self.session = ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])

    def unload(self) -> None:
        self.session = None

    def embed(self, audio: np.ndarray) -> np.ndarray:
        """L2-normalised 256-dim speaker embedding."""
        self.load()
        feats = fbank(audio)
        feats = feats - feats.mean(axis=0, keepdims=True)  # cepstral mean normalisation
        emb = self.session.run(None, {"feats": feats[None]})[0][0]
        return emb / (np.linalg.norm(emb) + 1e-9)

    @staticmethod
    def similarity(a: np.ndarray, b: np.ndarray) -> float:
        return float(np.dot(a, b))
