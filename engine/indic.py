"""Hindi / Gujarati speech in their own script, with AI4Bharat IndicConformer.

Whisper writes Gujarati poorly even with large-v3 (tested on the user's speech:
broken spellings, 30-90 s for a 15-20 s phrase). IndicConformer 600M, trained on
Indian speech, got the same recordings nearly right in 2-3 s on the CPU. Whisper
still decides English vs Indian language and writes English.

The model is gated on Hugging Face (accept its terms once, then the token in
Settings downloads it). It runs on onnxruntime + a small TorchScript feature
extractor, so torch is loaded in this process only once it is first used.

Memory: the encoder's 2.4 GB of float32 weights are quantized once to int8
(matrix multiplications only) and cached: 1.0 GB loaded instead of 2.4 GB, 35%
faster, same text on the user's recordings. Quantizing the convolutions too, or
without `reduce_range` (this Ryzen has no VNNI, so int8 products overflow), made
it return empty text.

  python indic.py --quantize SRC DST   (run by the engine in a child process)
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import threading
import time
import types

import numpy as np

REPO = "ai4bharat/indic-conformer-600m-multilingual"
# Languages it writes (of the ones Voice Desk offers).
LANGS = {"hi", "gu", "mr", "bn", "pa", "ta", "te", "kn", "ml", "ur", "ne", "or", "as", "sa", "sd"}
# Longer inputs are split, at pauses where possible. Measured on the user's
# recordings: up to 14 s is always decoded fully, but from ~16 s the output is
# erratic, often empty or missing the start (the model saw short utterances).
MAX_CHUNK_S = 12


def log(*args) -> None:
    print("[indic]", *args, file=sys.stderr, flush=True)


def quantize(src: str, dst: str) -> None:
    from onnxruntime.quantization import QuantType, quantize_dynamic

    tmp = dst + ".part"
    quantize_dynamic(
        src, tmp, weight_type=QuantType.QInt8, op_types_to_quantize=["MatMul", "Gemm"], per_channel=True, reduce_range=True
    )
    os.replace(tmp, dst)


def int8_encoder(snapshot: str) -> str | None:
    """Path of the cached int8 encoder, creating it (~1 min, once) if needed.
    Runs in a child process: quantizing briefly takes several GB of RAM."""
    cache = os.path.join(os.path.expanduser("~"), ".cache", "voicedesk")
    dst = os.path.join(cache, f"indic-encoder-int8-{os.path.basename(snapshot)}.onnx")
    if os.path.exists(dst):
        return dst
    os.makedirs(cache, exist_ok=True)
    log("making a smaller copy of the model (once, about a minute)...")
    proc = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "--quantize", os.path.join(snapshot, "assets", "encoder.onnx"), dst],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=1800,
        creationflags=0x08000000 if os.name == "nt" else 0,  # CREATE_NO_WINDOW
    )
    if proc.returncode != 0 or not os.path.exists(dst):
        log(f"quantizing failed, using the full-size model: {proc.stderr.strip().splitlines()[-1:]}")
        return None
    return dst


class IndicASR:
    def __init__(self) -> None:
        self.model = None
        self.failed: str | None = None  # why loading failed; don't retry every phrase
        self.last_used = time.time()
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self.model is not None

    @property
    def usable(self) -> bool:
        """Can be used (or loaded) — i.e. it hasn't failed to load."""
        return self.failed is None

    def load(self, hf_token: str | None = None) -> bool:
        """Load once; returns False (and remembers why) if it can't be used."""
        with self._lock:
            if self.model is not None:
                return True
            if self.failed:
                return False
            try:
                from huggingface_hub import snapshot_download

                t = time.time()
                try:
                    path = snapshot_download(REPO, local_files_only=True)
                except Exception:  # noqa: BLE001 — not downloaded yet
                    log("downloading IndicConformer (2.4 GB)...")
                    path = snapshot_download(REPO, token=hf_token or os.environ.get("HF_TOKEN") or None)
                # The repo's own inference code (transformers "remote code"), loaded
                # from the local snapshot so no network is needed after the download.
                spec = importlib.util.spec_from_file_location("indic_conformer_onnx", os.path.join(path, "model_onnx.py"))
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                encoder = int8_encoder(path)
                mod.ort = types.SimpleNamespace(InferenceSession=_session_factory(encoder))
                self.model = mod.IndicASRModel(mod.IndicASRConfig(ts_folder=path, FRAME_DURATION_MS=0.08))
                log(f"ready in {time.time() - t:.1f}s")
                return True
            except Exception as e:  # noqa: BLE001
                msg = str(e)
                if "gated" in msg.lower() or "403" in msg:
                    msg = f"accept the model's terms at https://huggingface.co/{REPO} ({msg.splitlines()[0]})"
                self.failed = msg
                log(f"unavailable, using Whisper instead: {msg}")
                return False

    def unload(self) -> None:
        with self._lock:
            self.model = None
            self.failed = None

    def transcribe(self, audio: np.ndarray, lang: str, choices: list[str] | None = None) -> tuple[str, str]:
        """(text, language) of 16 kHz mono float32 audio, in the language's script.

        `choices` (e.g. ["hi", "gu"]): the language is picked among these from
        the first chunk's sound, staying with `lang` unless another clearly fits
        better. Whisper can't tell Hindi from Gujarati; this can (see `_pick`)."""
        import torch

        model = self.model
        if model is None:
            raise RuntimeError("IndicConformer not loaded")
        self.last_used = time.time()
        step = MAX_CHUNK_S * 16000
        parts = []
        with self._lock, torch.inference_mode():
            for i in range(0, len(audio), step):
                piece = audio[i : i + step]
                if len(piece) < 1600:  # < 0.1 s
                    continue
                # The user's mic records quietly (peaks 0.02-0.07); at that level the
                # model dropped whole sentences. Raised to a 0.5 peak, it kept them.
                peak = float(np.abs(piece).max())
                if 0 < peak < 0.5:
                    piece = piece * min(0.5 / peak, 30.0)
                enc, lens = model.encode(torch.from_numpy(np.ascontiguousarray(piece)).unsqueeze(0))
                if i == 0 and choices and len(choices) > 1:
                    lang = self._pick(enc, lang, choices)
                # RNNT decoding: more accurate than CTC on the user's recordings.
                parts.append(model._rnnt_decode(enc, lens, lang))
        self.last_used = time.time()
        return " ".join(p for p in parts if p).strip(), lang

    # How much better (mean log-prob per letter) another language must fit to
    # override the preferred one. Measured on the user's recordings: Hindi fits
    # 0.14-0.20 better than Gujarati on Hindi speech, and 0.00-0.08 worse on
    # Gujarati speech.
    PICK_MARGIN = 0.08

    def _pick(self, enc, prefer: str, choices: list[str]) -> str:
        """Which language's letters explain the audio best, from the CTC head:
        each language's vocabulary is scored on its own, on non-silent frames."""
        import torch

        model = self.model
        logprobs = model.models["ctc_decoder"].run(["logprobs"], {"encoder_output": enc})[0][0]
        scores = {}
        for code in choices:
            lp = torch.from_numpy(logprobs[:, model.language_masks[code]]).log_softmax(-1)
            best, idx = lp.max(-1)
            spoken = idx != model.config.BLANK_ID
            if spoken.any():
                scores[code] = float(best[spoken].mean())
        if not scores:
            return prefer
        top = max(scores, key=scores.get)
        base = scores.get(prefer, float("-inf"))
        choice = top if top != prefer and scores[top] - base > self.PICK_MARGIN else prefer
        log(f"language {choice} ({', '.join(f'{k} {v:.2f}' for k, v in scores.items())})")
        return choice


def _session_factory(encoder: str | None):
    """onnxruntime sessions for the model's loader: the int8 encoder instead of
    the float32 one, and no memory arena (it kept the largest input's buffers)."""
    import onnxruntime as ort

    def session(path: str, providers=None):
        if encoder and os.path.normpath(path).endswith(os.path.join("assets", "encoder.onnx")):
            path = encoder
        opts = ort.SessionOptions()
        opts.enable_cpu_mem_arena = False
        # onnxruntime would use every core; share them with the rest of the computer.
        opts.intra_op_num_threads = int(os.environ.get("OMP_NUM_THREADS") or 2)
        opts.inter_op_num_threads = 1
        return ort.InferenceSession(path, opts, providers=providers)

    return session


indic_asr = IndicASR()


def wanted(languages: list[str] | None, translate) -> bool:
    """Will any of these languages be written in its own script (not translated)?"""
    for lang in languages or []:
        if lang in LANGS and not (translate is True or (isinstance(translate, list) and lang in translate)):
            return True
    return False


if __name__ == "__main__" and len(sys.argv) == 4 and sys.argv[1] == "--quantize":
    quantize(sys.argv[2], sys.argv[3])
