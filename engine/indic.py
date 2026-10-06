"""Hindi / Gujarati speech in their own script, with AI4Bharat IndicConformer.

Whisper writes Gujarati poorly even with large-v3 (tested on the user's speech:
broken spellings, 30-90 s for a 15-20 s phrase). IndicConformer 600M, trained on
Indian speech, got the same recordings nearly right in 2-3 s on the CPU. Whisper
still decides English vs Indian language and writes English.

The model is gated on Hugging Face (accept its terms once, then the token in
Settings downloads it). It runs on onnxruntime alone: the repo's own inference
code needs PyTorch and transformers (~0.7 GB to install, no Intel-Mac builds,
and importing transformers took ~14 s of the ~30 s load), so its steps are
redone here (`Conformer`, `features`). Now ready in ~4 s, ~0.4 GB less RAM.

Memory: the encoder's 2.4 GB of float32 weights are quantized once to int8
(matrix multiplications only) and cached: 1.0 GB loaded instead of 2.4 GB, 35%
faster, same text on the user's recordings. Quantizing the convolutions too, or
without `reduce_range` (this Ryzen has no VNNI, so int8 products overflow), made
it return empty text.

  python indic.py --quantize SRC DST   (run by the engine in a child process)
"""

from __future__ import annotations

import gc
import json
import os
import subprocess
import sys
import threading
import time

import numpy as np

REPO = "ai4bharat/indic-conformer-600m-multilingual"
DOWNLOAD_NAME = "Hindi/Gujarati model (IndicConformer)"
# Languages it writes (of the ones Voice Desk offers).
LANGS = {"hi", "gu", "mr", "bn", "pa", "ta", "te", "kn", "ml", "ur", "ne", "or", "as", "sa", "sd"}
# Longer inputs are split, at pauses where possible. Measured on the user's
# recordings: up to 14 s is always decoded fully, but from ~16 s the output is
# erratic, often empty or missing the start (the model saw short utterances).
MAX_CHUNK_S = 12
# RNNT silent this long: CTC's words are used there (`IndicASR._ctc_fill`).
CTC_FILL_S = 2.0


def uncovered(words: list[dict], start: float, end: float, min_s: float) -> list[tuple[float, float]]:
    """Stretches of at least `min_s` within [start, end) without any of `words` ({"s", "e"})."""
    out, at = [], start
    for w in sorted(words, key=lambda w: w["s"]):
        if w["s"] - at >= min_s:
            out.append((at, w["s"]))
        at = max(at, w["e"])
    if end - at >= min_s:
        out.append((at, end))
    return out


def log(*args) -> None:
    print("[indic]", *args, file=sys.stderr, flush=True)


def quantize(src: str, dst: str) -> None:
    from onnxruntime.quantization import QuantType, quantize_dynamic

    tmp = dst + ".part"
    quantize_dynamic(
        src, tmp, weight_type=QuantType.QInt8, op_types_to_quantize=["MatMul", "Gemm"], per_channel=True, reduce_range=True
    )
    os.replace(tmp, dst)


def int8_path(snapshot: str) -> str:
    from runtime import models_dir

    return os.path.join(models_dir(), f"indic-encoder-int8-{os.path.basename(snapshot)}.onnx")


def local_snapshot() -> str | None:
    """The downloaded model's folder, if it's usable without the internet.

    Not `snapshot_download(local_files_only=True)`: once the int8 copy exists the
    full-size weights are deleted, and huggingface_hub then calls the snapshot
    incomplete. That made every start download 2.4 GB again, and offline
    Hindi/Gujarati didn't work at all."""
    from huggingface_hub import try_to_load_from_cache

    found = try_to_load_from_cache(REPO, "model_onnx.py")
    if not isinstance(found, str):
        return None
    snapshot = os.path.dirname(found)
    if os.path.exists(int8_path(snapshot)) or float_encoder_complete(snapshot):
        return snapshot
    return None


def int8_encoder(snapshot: str) -> str | None:
    """Path of the int8 encoder, creating it (~1 min, once) if needed.
    Runs in a child process: quantizing briefly takes several GB of RAM."""
    name = os.path.basename(int8_path(snapshot))
    dst = int8_path(snapshot)
    old = os.path.join(os.path.expanduser("~"), ".cache", "voicedesk", name)  # before models_dir()
    if not os.path.exists(dst) and os.path.exists(old):
        os.replace(old, dst)
    if os.path.exists(dst):
        prune_float_encoder(snapshot)
        return dst
    src = os.path.join(snapshot, "assets", "encoder.onnx")
    if not float_encoder_complete(snapshot):
        return None  # originals were pruned and the copy is gone: the caller downloads them again
    log("making a smaller copy of the model (once, about a minute)...")
    proc = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "--quantize", src, dst],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=1800,
        creationflags=0x08000000 if os.name == "nt" else 0,  # CREATE_NO_WINDOW
    )
    if proc.returncode != 0 or not os.path.exists(dst):
        log(f"quantizing failed, using the full-size model: {proc.stderr.strip().splitlines()[-1:]}")
        return None
    prune_float_encoder(snapshot)
    return dst


def _encoder_weight_files(snapshot: str) -> list[str]:
    """The full-size encoder's weight files (366 files, ~2.4 GB, next to encoder.onnx)."""
    import onnx

    assets = os.path.join(snapshot, "assets")
    model = onnx.load(os.path.join(assets, "encoder.onnx"), load_external_data=False)
    names = {e.value for t in model.graph.initializer for e in t.external_data if e.key == "location"}
    return [os.path.join(assets, n) for n in names]


def float_encoder_complete(snapshot: str) -> bool:
    try:
        return all(os.path.exists(f) for f in _encoder_weight_files(snapshot))
    except Exception:  # noqa: BLE001
        return False


def prune_float_encoder(snapshot: str) -> None:
    """Once the int8 copy exists the full-size weights are never read: free ~2.4 GB."""
    try:
        files = [f for f in _encoder_weight_files(snapshot) if os.path.exists(f)]
    except Exception as e:  # noqa: BLE001
        log(f"couldn't list the full-size encoder: {e}")
        return
    freed = 0
    for f in files:
        try:
            freed += os.path.getsize(f)
            os.remove(f)
        except OSError:
            pass
    if freed:
        log(f"removed the full-size encoder ({freed / 1e9:.1f} GB); the int8 copy is used")


def _louder(piece: np.ndarray) -> np.ndarray:
    """The user's mic records quietly (peaks 0.02-0.07); at that level the model
    dropped whole sentences. Raised to a 0.5 peak, it kept them."""
    peak = float(np.abs(piece).max()) if len(piece) else 0.0
    return piece * min(0.5 / peak, 30.0) if 0 < peak < 0.5 else piece


class IndicASR:
    # After failing to load (no internet, terms not accepted yet...), try again
    # this much later, or at once with a different Hugging Face token. It used
    # to stay off until Voice Desk was restarted.
    RETRY_AFTER_S = 10 * 60

    def __init__(self) -> None:
        self.model = None
        self.failed: str | None = None  # why loading failed; don't retry every phrase
        self.failed_at = 0.0
        self.failed_token: str | None = None
        self.last_used = time.time()
        self._load_lock = threading.Lock()  # held while loading: minutes when downloading
        self._run_lock = threading.Lock()  # one decoding at a time

    @property
    def loaded(self) -> bool:
        return self.model is not None

    @property
    def loading(self) -> bool:
        return self._load_lock.locked()

    @property
    def usable(self) -> bool:
        """Can be used (or loaded): it hasn't failed to load, or long enough ago to try again."""
        return self.failed is None or time.time() - self.failed_at >= self.RETRY_AFTER_S

    def _may_try(self, hf_token: str | None) -> bool:
        return self.usable or bool(hf_token and hf_token != self.failed_token)

    def load_in_background(self, hf_token: str | None = None) -> None:
        """Start loading without waiting for it (live dictation doesn't wait)."""
        if not self.loaded and not self.loading and self._may_try(hf_token):
            threading.Thread(target=self.load, args=(hf_token,), daemon=True).start()

    def load(self, hf_token: str | None = None) -> bool:
        """Load once; returns False (and remembers why) if it can't be used."""
        if self.model is not None:  # no lock: checked for every phrase, and loading holds it for minutes
            return True
        with self._load_lock:
            if self.model is not None:
                return True
            if not self._may_try(hf_token):
                return False
            try:
                from runtime import hub_snapshot

                t = time.time()
                token = hf_token or os.environ.get("HF_TOKEN") or None
                path = local_snapshot()
                if path is None:
                    log("downloading IndicConformer (2.4 GB)...")
                    path = hub_snapshot(REPO, DOWNLOAD_NAME, token)
                encoder = int8_encoder(path)
                if encoder is None and not float_encoder_complete(path):
                    log("downloading the model's full-size encoder again to rebuild the small copy...")
                    path = hub_snapshot(REPO, DOWNLOAD_NAME, token)
                    encoder = int8_encoder(path)
                self.model = Conformer(path, encoder)
                self.failed = None
                log(f"ready in {time.time() - t:.1f}s")
                return True
            except Exception as e:  # noqa: BLE001
                msg = str(e)
                if "gated" in msg.lower() or "403" in msg:
                    msg = f"accept the model's terms at https://huggingface.co/{REPO} ({msg.splitlines()[0]})"
                self.failed, self.failed_at, self.failed_token = msg, time.time(), hf_token
                log(f"unavailable, using Whisper instead (trying again in {self.RETRY_AFTER_S // 60} min): {msg}")
                return False

    def unload(self) -> None:
        """Free its ~1 GB of RAM. A decoding still running keeps its own reference."""
        with self._load_lock:
            self.model = None
        gc.collect()

    def pick(self, audio: np.ndarray, prefer: str, choices: list[str]) -> str:
        """Which of `choices` (e.g. ["hi", "gu"]) this speech is in, from its
        first chunk (see `_pick`); `prefer` unless another clearly fits better."""
        model = self.model
        piece = audio[: MAX_CHUNK_S * 16000]
        if model is None or len(piece) < 1600:
            return prefer
        self.last_used = time.time()
        with self._run_lock:
            enc, _ = model.encode(_louder(piece))
            return self._pick(model, enc, prefer, choices)

    def transcribe_words(self, audio: np.ndarray, lang: str, choices: list[str] | None = None) -> tuple[list[dict], str]:
        """([{"w", "s", "e"}], language) of 16 kHz mono float32 audio, in the
        language's script; times in seconds from the start of `audio`.

        `choices` (e.g. ["hi", "gu"]): the language is picked among these from
        the first chunk's sound, staying with `lang` unless another clearly fits
        better. Whisper can't tell Hindi from Gujarati; this can (see `_pick`)."""
        model = self.model
        if model is None:
            raise RuntimeError("IndicConformer not loaded")
        self.last_used = time.time()
        step = MAX_CHUNK_S * 16000
        words: list[dict] = []
        with self._run_lock:
            for i in range(0, len(audio), step):
                piece = audio[i : i + step]
                if len(piece) < 1600:  # < 0.1 s
                    continue
                enc, lens = model.encode(_louder(piece))
                if i == 0 and choices and len(choices) > 1:
                    lang = self._pick(model, enc, lang, choices)
                # RNNT decoding: more accurate than CTC on the user's recordings.
                offset = i / 16000
                rnnt = self._decode_words(model, enc, lang, offset)
                fill = self._ctc_fill(model, enc, lens, lang, rnnt, offset, len(piece) / 16000)
                words += sorted(rnnt + fill, key=lambda w: w["s"])
        self.last_used = time.time()
        return words, lang

    @staticmethod
    def _ctc_fill(model, enc, lens, lang: str, rnnt: list[dict], offset: float, seconds: float) -> list[dict]:
        """CTC's words where RNNT wrote nothing for CTC_FILL_S or longer.

        RNNT decoding sometimes outputs nothing at all for a stretch, or a whole
        chunk, depending only on where the audio starts (17.0-22.0 s of the
        user's test meeting came out right, 17.6-22.0 s and 16.0-23.0 s empty),
        while CTC on the same encoder output still has the words (rougher). It
        costs one small extra step."""
        gaps = uncovered(rnnt, offset, offset + seconds, CTC_FILL_S)
        if not gaps:
            return []
        logprobs = model.models["ctc_decoder"].run(["logprobs"], {"encoder_output": enc})[0][0]
        path = np.argmax(logprobs[: int(lens[0]), model.language_masks[lang]], axis=-1)
        # Greedy CTC: a token repeated over frames counts once; blanks separate.
        pieces, prev = [], None
        for t, token in enumerate(path.tolist()):
            if token != prev and token != model.BLANK_ID:
                pieces.append((model.vocab[lang][token], t))
            prev = token
        fill = [
            dict(w, ctc=True)
            for w in _words(pieces, offset, model.FRAME_S)
            if any(a <= (w["s"] + w["e"]) / 2 < b for a, b in gaps)
        ]
        if fill:
            log(f"{len(fill)} words from CTC where RNNT wrote nothing")
        return fill

    @staticmethod
    def _decode_words(model, enc, lang: str, offset: float) -> list[dict]:
        """The model's own greedy RNNT decoding (`_rnnt_decode` in the repo's
        model_onnx.py, same steps and text), also noting the encoder frame each
        piece came out at: words get real times instead of being spread evenly
        over the phrase."""
        joint_enc = model.models["joint_enc"].run(["output"], {"input": enc.transpose(0, 2, 1)})[0]
        post_net = model.post_net(lang)
        hyp = [model.SOS]
        frames: list[int] = []
        state = (
            np.zeros((model.PRED_RNN_LAYERS, 1, model.PRED_RNN_HIDDEN_DIM), dtype=np.float32),
            np.zeros((model.PRED_RNN_LAYERS, 1, model.PRED_RNN_HIDDEN_DIM), dtype=np.float32),
        )
        for t in range(joint_enc.shape[1]):
            f = joint_enc[:, t : t + 1, :]
            added = 0
            while added < model.RNNT_MAX_SYMBOLS:
                g, _, s0, s1 = model.models["rnnt_decoder"].run(
                    ["outputs", "prednet_lengths", "states", "162"],
                    {"targets": np.array([[hyp[-1]]], dtype=np.int32), "target_length": np.array([1], dtype=np.int32),
                     "states.1": state[0], "onnx::Slice_3": state[1]},
                )
                g = model.models["joint_pred"].run(["output"], {"input": g.transpose(0, 2, 1)})[0]
                joint = model.models["joint_pre_net"].run(["output"], {"input": f + g})[0]
                logits = post_net.run(["output"], {"input": joint})[0]
                token = int(np.argmax(logits, axis=-1).item())
                added += 1
                if token == model.BLANK_ID:
                    break
                hyp.append(token)
                frames.append(t)
                state = (s0, s1)
        pieces = [(model.vocab[lang][token], t) for token, t in zip(hyp[1:], frames)]
        return _words(pieces, offset, model.FRAME_S)

    # How much better (mean log-prob per letter) another language must fit to
    # override the preferred one. Measured on the user's recordings: Hindi fits
    # 0.14-0.20 better than Gujarati on Hindi speech, and 0.00-0.08 worse on
    # Gujarati speech.
    PICK_MARGIN = 0.08

    def _pick(self, model, enc, prefer: str, choices: list[str]) -> str:
        """Which language's letters explain the audio best, from the CTC head:
        each language's vocabulary is scored on its own, on non-silent frames."""
        logprobs = model.models["ctc_decoder"].run(["logprobs"], {"encoder_output": enc})[0][0]
        scores = {}
        for code in choices:
            lp = _log_softmax(logprobs[:, model.language_masks[code]])
            best, idx = lp.max(-1), lp.argmax(-1)
            spoken = idx != model.BLANK_ID
            if spoken.any():
                scores[code] = float(best[spoken].mean())
        if not scores:
            return prefer
        top = max(scores, key=scores.get)
        base = scores.get(prefer, float("-inf"))
        choice = top if top != prefer and scores[top] - base > self.PICK_MARGIN else prefer
        log(f"language {choice} ({', '.join(f'{k} {v:.2f}' for k, v in scores.items())})")
        return choice


def _words(pieces: list[tuple[str, int]], offset: float, step: float) -> list[dict]:
    """Decoded pieces ("▁ગુ", "જ", ...) with their encoder frame -> words with
    times (s). "▁" starts a word; `step`: seconds per frame (0.08)."""
    words: list[dict] = []
    for piece, t in pieces:
        at = round(offset + t * step, 2)
        text = piece.replace("▁", "")
        if piece.startswith("▁") or not words:
            if words and not words[-1]["w"]:
                words.pop()  # a lone "▁" before this one
            words.append({"w": "", "s": at, "e": at})
        if text and not words[-1]["w"]:
            words[-1]["s"] = at
        words[-1]["w"] += text
        words[-1]["e"] = round(at + step, 2)
    return [w for w in words if w["w"].strip()]


def _log_softmax(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float64)
    x = x - x.max(-1, keepdims=True)
    return x - np.log(np.exp(x).sum(-1, keepdims=True))


def _mel_filterbank() -> np.ndarray:
    """(257, 80): the preprocessor's mel filters (librosa's: Slaney mel scale and
    area normalization, 0-8 kHz, 512-point FFT at 16 kHz). Within 7e-8 of the
    matrix stored in the repo's preprocessor.ts (float32 rounding)."""

    def to_mel(hz: float) -> float:
        return 15 + np.log(hz / 1000) / (np.log(6.4) / 27) if hz >= 1000 else hz / (200 / 3)

    mels = np.linspace(to_mel(0.0), to_mel(8000.0), 82)
    hz = np.where(mels >= 15, 1000 * np.exp(np.log(6.4) / 27 * (mels - 15)), mels * (200 / 3))
    ramps = hz[:, None] - np.fft.rfftfreq(512, 1 / 16000)[None, :]
    fb = np.maximum(0, np.minimum(-ramps[:-2] / np.diff(hz)[:-1, None], ramps[2:] / np.diff(hz)[1:, None]))
    return (fb * (2.0 / (hz[2:] - hz[:-2]))[:, None]).T


_MEL = _mel_filterbank()
# A 400-sample (25 ms) symmetric Hann window, centered in the 512-point frame.
_WINDOW = np.pad(0.5 - 0.5 * np.cos(2 * np.pi * np.arange(400) / 399), 56)


def features(audio: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The model's input from 16 kHz mono audio: ((1, 80, frames) float32, [frames]).

    The repo's preprocessor.ts (NeMo's, traced to TorchScript) redone in NumPy:
    0.97 pre-emphasis, |STFT|^2 (10 ms hop, reflect-padded), 80 mel bands,
    log(x + 2^-24), then each band normalized to mean 0 / std 1 over the clip.
    No dither (the traced copy has none). On 30 clips of the user's test meeting
    it differs from the TorchScript by at most 1e-4 (mean ~1e-6; the features
    have std 1); bit-identical isn't possible (torch's FFT is MKL's).

    The text can still differ in places: the int8 encoder amplifies the
    smallest input change. Gaussian noise of 1e-6 added to the TorchScript's
    own features changed ~13% of the words on that meeting, and these features
    changed as many (102 vs 101 edits in 784 words, 63 twelve-second windows),
    and wrote no fewer words."""
    x = np.asarray(audio, dtype=np.float32)
    y = x.copy()
    y[1:] -= x[:-1] * np.float32(0.97)
    y = np.pad(y.astype(np.float64), 256, mode="reflect")
    frames = np.lib.stride_tricks.sliding_window_view(y, 512)[::160]
    power = np.abs(np.fft.rfft(frames * _WINDOW, axis=-1)) ** 2
    feats = np.log(power @ _MEL + 2.0**-24).T
    n = feats.shape[1]
    feats -= feats.mean(axis=1, keepdims=True)
    std = np.sqrt(np.maximum((feats**2).sum(axis=1, keepdims=True) / max(n - 1, 1), 2.0**-24))
    return (feats / (std + 1e-5)).astype(np.float32)[None], np.array([n], dtype=np.int64)


class Conformer:
    """The model's ONNX parts, vocabularies and settings, read from its
    downloaded folder without the repo's model_onnx.py (which needs torch and
    transformers just to hold them)."""

    # model_onnx.py's `IndicASRConfig` defaults, which its loader runs with: it
    # never reads config.json, whose "SOS": 256 would be an Assamese letter.
    # 5632 is the shared blank after the 22 languages' 22 x 256 tokens, which
    # the RNNT decoder starts from. BLANK_ID is the blank's index within one
    # language's 257 (`language_masks`).
    BLANK_ID = 256
    SOS = 5632
    RNNT_MAX_SYMBOLS = 10
    PRED_RNN_LAYERS = 2
    PRED_RNN_HIDDEN_DIM = 640
    FRAME_S = 0.08  # seconds per encoder frame

    def __init__(self, snapshot: str, encoder: str | None) -> None:
        self.assets = os.path.join(snapshot, "assets")
        self.models = {
            name: _session(encoder if name == "encoder" and encoder else os.path.join(self.assets, f"{name}.onnx"))
            for name in ("encoder", "ctc_decoder", "rnnt_decoder", "joint_enc", "joint_pred", "joint_pre_net")
        }
        with open(os.path.join(self.assets, "vocab.json"), encoding="utf-8") as f:
            self.vocab: dict[str, list[str]] = json.load(f)
        with open(os.path.join(self.assets, "language_masks.json"), encoding="utf-8") as f:
            self.language_masks = {k: np.array(v, dtype=bool) for k, v in json.load(f).items()}

    def post_net(self, lang: str):
        """The language's own last layer (one of 22, 0.7 MB each), loaded when first used."""
        name = f"joint_post_net_{lang}"
        if name not in self.models:
            self.models[name] = _session(os.path.join(self.assets, f"{name}.onnx"))
        return self.models[name]

    def encode(self, audio: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """(encoder output (1, 1024, frames), [frames]) of 16 kHz mono audio."""
        feats, length = features(audio)
        return tuple(self.models["encoder"].run(["outputs", "encoded_lengths"], {"audio_signal": feats, "length": length}))


def _session(path: str):
    """An onnxruntime session without a memory arena (it kept the largest
    input's buffers)."""
    import onnxruntime as ort

    opts = ort.SessionOptions()
    opts.enable_cpu_mem_arena = False
    # onnxruntime would use every core; share them with the rest of the computer.
    opts.intra_op_num_threads = int(os.environ.get("OMP_NUM_THREADS") or 2)
    opts.inter_op_num_threads = 1
    # Idle worker threads would otherwise spin, burning CPU between steps:
    # measured ~9-11 cores busy while decoding with a 4-thread limit.
    opts.add_session_config_entry("session.intra_op.allow_spinning", "0")
    opts.add_session_config_entry("session.inter_op.allow_spinning", "0")
    return ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])


indic_asr = IndicASR()


def wanted(languages: list[str] | None, translate) -> bool:
    """Will any of these languages be written in its own script (not translated)?"""
    for lang in languages or []:
        if lang in LANGS and not (translate is True or (isinstance(translate, list) and lang in translate)):
            return True
    return False


if __name__ == "__main__" and len(sys.argv) == 4 and sys.argv[1] == "--quantize":
    quantize(sys.argv[2], sys.argv[3])
