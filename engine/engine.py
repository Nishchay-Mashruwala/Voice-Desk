"""Voice Desk speech engine.

Long-running sidecar spawned by the Tauri backend. Speaks JSON Lines:

  stdin  <- {"id": 1, "cmd": "transcribe", ...}         request (gets exactly one reply)
            {"cmd": "audio", "sid": 1, "pcm": "<b64>"}   live microphone audio (no reply)
  stdout -> {"id": 1, "ok": true, "result": {...}}       reply
            {"id": 1, "event": "progress", ...}          progress for a request
            {"event": "utterance", "sid": 1, ...}        live dictation result

Only protocol messages go to stdout; all logging goes to stderr.

Memory: Whisper lives on the GPU when there is one; the voice-ID model is a
26 MB ONNX file; torch/pyannote only ever load in a short-lived subprocess
(diarize.py). Idle models are unloaded after a configurable time.

  python engine.py --prefetch   downloads models ahead of time (used by setup)
"""

from __future__ import annotations

import base64
import gc
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import wave
from typing import Any, Callable


def _worker_threads() -> int:
    """CPU threads for heavy work: half the physical cores, at least 2.

    Measured on an 8-core laptop: with every library using all cores, live
    dictation of Gujarati peaked at 14.6 of 16 threads and transcription at 14.9,
    making the whole computer stutter. Voice Desk runs on many kinds of laptops,
    so this follows the machine instead of a fixed number."""
    try:
        import psutil

        cores = psutil.cpu_count(logical=False)
    except Exception:  # noqa: BLE001
        cores = None
    cores = cores or max(1, (os.cpu_count() or 4) // 2)
    return max(2, cores // 2)


# Before numpy/torch/onnxruntime load: they size their thread pools from these.
THREADS = int(os.environ.get("VOICEDESK_THREADS") or _worker_threads())
for _var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
    os.environ.setdefault(_var, str(THREADS))

import numpy as np  # noqa: E402

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")


def _add_cuda_dll_dirs() -> None:
    """Make pip-installed CUDA libs (nvidia-cublas-cu12, nvidia-cudnn-cu12) loadable.

    Only relevant on Windows/Linux with an NVIDIA GPU; macOS has no CUDA and
    Whisper simply runs on the CPU there.
    """
    import site

    for base in site.getsitepackages():
        nvidia = os.path.join(base, "nvidia")
        if not os.path.isdir(nvidia):
            continue
        for pkg in os.listdir(nvidia):
            if os.name == "nt":
                bin_dir = os.path.join(nvidia, pkg, "bin")
                if os.path.isdir(bin_dir):
                    os.add_dll_directory(bin_dir)
                    os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
            else:
                # Linux ignores LD_LIBRARY_PATH changes after startup, so preload the libs.
                import ctypes
                import glob

                for lib in sorted(glob.glob(os.path.join(nvidia, pkg, "lib", "*.so*"))):
                    try:
                        ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
                    except OSError:
                        pass


_add_cuda_dll_dirs()

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import commands  # noqa: E402
import indic  # noqa: E402
from indic import indic_asr  # noqa: E402
from voiceprint import VoicePrint  # noqa: E402

SAMPLE_RATE = 16000
_out_lock = threading.Lock()

# Protocol streams. `main()` swaps these for private copies of the original pipes.
_proto_in = sys.stdin
_proto_out = sys.stdout


def log(*args: Any) -> None:
    print("[engine]", *args, file=sys.stderr, flush=True)


def send(msg: dict) -> None:
    line = json.dumps(msg, ensure_ascii=False)
    with _out_lock:
        _proto_out.write(line + "\n")
        _proto_out.flush()


def read_wav(path: str) -> np.ndarray:
    """Read a 16 kHz mono 16-bit WAV (what the Rust recorder writes) as float32."""
    with wave.open(path, "rb") as w:
        if w.getframerate() != SAMPLE_RATE or w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError(
                f"{path}: expected 16kHz mono s16, got {w.getframerate()}Hz "
                f"{w.getnchannels()}ch {w.getsampwidth() * 8}bit"
            )
        frames = w.readframes(w.getnframes())
    return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0


def write_wav(path: str, audio: np.ndarray) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())


# --------------------------------------------------------------------------- #
# Voice activity detection (Silero, bundled with faster-whisper)
# --------------------------------------------------------------------------- #


def speech_spans(audio: np.ndarray, min_silence_ms: int = 500, pad_ms: int = 150) -> list[dict]:
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    if len(audio) < SAMPLE_RATE // 4:
        return []
    return get_speech_timestamps(
        audio,
        VadOptions(threshold=0.5, min_speech_duration_ms=200, min_silence_duration_ms=min_silence_ms, speech_pad_ms=pad_ms),
    )


def speech_only(audio: np.ndarray) -> np.ndarray:
    spans = speech_spans(audio, min_silence_ms=300, pad_ms=50)
    if not spans:
        return np.zeros(0, np.float32)
    return np.concatenate([audio[s["start"] : s["end"]] for s in spans])


def speech_seconds(audio: np.ndarray) -> float:
    return sum(s["end"] - s["start"] for s in speech_spans(audio)) / SAMPLE_RATE


def is_real_speech(audio: np.ndarray) -> bool:
    """Reject background noise (keyboard, breathing, fans) before Whisper can
    turn it into words like "Thank you.".

    Measured on real recordings: noise scores a mean speech probability of
    0.02-0.17 with no confident frames; actual speech, even quiet short commands,
    scores 0.6-0.8 with at least ~0.4 s of confident speech.
    """
    from faster_whisper.vad import get_vad_model

    if len(audio) < SAMPLE_RATE // 5:
        return False
    padded = np.pad(audio, (0, 512 - len(audio) % 512))
    probs = np.asarray(get_vad_model()(padded)).ravel()
    confident_s = float((probs > 0.8).sum()) * 512 / SAMPLE_RATE
    return float(probs.mean()) >= 0.3 and confident_s >= 0.2


def collapse_repeats(text: str) -> str:
    """Undo Whisper's repetition loops on unclear audio: "I don't know, I don't
    know, I don't know" -> "I don't know". A multi-word phrase repeated 3+ times,
    or one word repeated 5+ times, is kept once ("Hello, hello, hello" stays).
    Works on whole words, so Hindi/Gujarati (with vowel signs) are handled too."""
    words = text.split()
    key = [w.strip(",.;:!?।").lower() for w in words]
    out: list[str] = []
    i = 0
    while i < len(words):
        collapsed = False
        for n in range(1, 9):
            if i + n > len(words):
                break
            reps = 1
            while key[i + reps * n : i + (reps + 1) * n] == key[i : i + n]:
                reps += 1
            if (n == 1 and reps >= 5) or (n >= 2 and reps >= 3):
                # Keep the first copy's wording with the last copy's closing punctuation.
                copy = list(words[i : i + n])
                tail = words[i + reps * n - 1]
                copy[-1] = copy[-1].rstrip(",.;:!?।") + tail[len(tail.rstrip(",.;:!?।")) :]
                out.extend(copy)
                i += reps * n
                collapsed = True
                break
        if not collapsed:
            out.append(words[i])
            i += 1
    return " ".join(out)


def echoes_vocabulary(text: str, vocabulary: str | None) -> bool:
    """Whisper sometimes repeats its prompt ("Mira, Nishchay, Voice Desk.")
    when the audio is unclear. True if the text is mostly vocabulary words."""
    if not vocabulary:
        return False
    vocab_words = {w.lower() for w in commands.WORD.findall(vocabulary)}
    words = [w.lower() for w in commands.WORD.findall(text)]
    if len(words) < 2:
        return False
    hits = sum(w in vocab_words for w in words)
    return hits >= 2 and hits / len(words) >= 0.6


# --------------------------------------------------------------------------- #
# Whisper
# --------------------------------------------------------------------------- #

# Languages Whisper may report for Indian speech (Gujarati is often called Hindi,
# Marathi or Urdu). Used to decide "English or Indian language?".
INDIC = {"hi", "gu", "mr", "ur", "bn", "pa", "ne", "sa", "ta", "te", "kn", "ml", "or", "as", "sd"}

def whisper_need(languages: list[str] | None, translate) -> str:
    """What Whisper must do: "english" (only English), "detect" (English, and
    telling it from Hindi/Gujarati that IndicConformer writes), or "indic"
    (write or translate Indian languages itself)."""
    indian = [lang for lang in languages or ["en"] if lang != "en"]
    if not indian:
        return "english"
    if all(lang in indic.LANGS and task_for(lang, translate) == "transcribe" for lang in indian) and indic_asr.usable:
        return "detect"
    return "indic"


def spread_words(text: str, start: float, end: float) -> list[dict]:
    """Approximate word timings across a phrase, proportional to word length."""
    words = text.split()
    weights = [len(w) + 1 for w in words]
    total = sum(weights) or 1
    out, t = [], start
    for w, wt in zip(words, weights):
        d = (end - start) * wt / total
        out.append({"w": w, "s": round(t, 2), "e": round(t + d, 2)})
        t += d
    return out


def untimed(seg: dict) -> dict:
    seg.pop("timed", None)
    return seg


def exact_words(words: bool | str, language: str | None, task: str) -> bool:
    """words="auto": exact word timings for English; for Hindi/Gujarati/translation
    they double the decoding time, so they're estimated from the phrase timing."""
    return words is True or (words == "auto" and language == "en" and task == "transcribe")


def task_for(language: str | None, translate: bool | list[str] | None) -> str:
    """Whisper task for this language. `translate`: True = every non-English
    language, or a list like ["gu"]. Translating Gujarati is ~4x faster than
    writing Gujarati script (Whisper spends 2-3 tokens per Gujarati letter)."""
    if not language or language == "en" or not translate:
        return "transcribe"
    if translate is True or language in translate:
        return "translate"
    return "transcribe"


# Whisper's favourite inventions on noise / silence.
HALLUCINATIONS = {
    "thank you", "thank you.", "thanks for watching", "thanks for watching!", "thank you for watching",
    "thank you for watching.", "you", "bye", "bye.", "subtitles by the amara.org community",
    "please subscribe", "i'll see you next time.", ".", "...",
}


# GPU memory each Whisper model needs (int8_float16), measured with its CUDA
# runtime: medium 1.1-1.2 GB on an RTX 3050. Others scaled by model size.
GPU_NEED_GB = {"large-v3": 2.0, "large-v3-turbo": 1.2, "medium": 1.2, "small": 0.6, "base": 0.4, "tiny": 0.3}
# Left free for the task AI's working memory and other apps.
GPU_SPARE_GB = 0.3


def parse_device(device: str | None) -> tuple[str, int]:
    """"auto" | "cpu" | "cuda" | "cuda:N" -> (kind, GPU number)."""
    device = (device or "auto").strip()
    if device.startswith("cuda:"):
        try:
            return "cuda", int(device[5:])
        except ValueError:
            return "cuda", 0
    return device, 0


def gpu_free_gb(index: int = 0) -> float | None:
    """Free memory on an NVIDIA GPU, or None if it can't be read."""
    try:
        flags = 0x08000000 if os.name == "nt" else 0
        out = subprocess.run(
            ["nvidia-smi", f"--id={index}", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5, creationflags=flags,
        ).stdout
        return float(out.strip().splitlines()[0]) / 1024
    except Exception:  # noqa: BLE001
        return None


def cpu_model() -> str:
    """Whisper on the CPU: small (~0.5 GB), or base on computers with little RAM."""
    try:
        import psutil

        if psutil.virtual_memory().total < 6 * 2**30:
            return "base"
    except Exception:  # noqa: BLE001
        pass
    return "small"


class Transcriber:
    def __init__(self) -> None:
        self.model = None
        self.config: tuple[str, str] | None = None
        self.active_device = "none"
        self.active_model = "none"
        self.last_used = time.time()
        self._lock = threading.Lock()

    @staticmethod
    def _candidates(model_name: str, device: str, need: str) -> list[tuple[str, str, int, str]]:
        """(model, device, compute_type) to try in order. 'auto' picks by hardware
        and what Whisper has to do (`need`, from `whisper_need`); on CPU, small.

        On an NVIDIA GPU: English only -> large-v3-turbo. Hindi/Gujarati written
        as spoken (IndicConformer writes them; Whisper only writes English and
        tells English from Indian speech) -> medium: on 62 of the user's phrases
        it told them apart as well as large-v3 (2 mistakes each), on ~1.1 GB of
        GPU memory instead of ~2 GB. turbo can't be used there: it called most of
        the user's Gujarati English. Translating -> large-v3, which translates best."""
        gpu_auto = {"english": "large-v3-turbo", "detect": "medium"}.get(need, "large-v3")
        dev, index = parse_device(device)
        out = []
        if dev in ("auto", "cuda"):
            free = gpu_free_gb(index)
            if model_name != "auto":
                names = [model_name]
            else:
                # Smaller GPUs (2-3 GB, or busy with other apps) get a model that fits,
                # instead of running out of memory or crowding out the task AI.
                names = [n for n in (gpu_auto, "small") if free is None or GPU_NEED_GB[n] <= free - GPU_SPARE_GB]
                if not names and dev == "cuda":
                    names = ["small"]  # pinned to this GPU: try the smallest anyway
                if free is not None:
                    log(f"GPU {index}: {free:.1f} GB free -> {names or 'too little, using the CPU'}")
            out += [(n, "cuda", index, "int8_float16") for n in names]
        if dev in ("auto", "cpu"):
            out.append((cpu_model() if model_name == "auto" else model_name, "cpu", 0, "int8"))
        return out

    def load(self, model_name: str = "auto", device: str = "auto", languages: list[str] | None = None, translate=False) -> None:
        need = whisper_need(languages, translate)
        with self._lock:
            self.last_used = time.time()
            if self.model is not None and self.config == (model_name, device, need):
                return
            self._unload()
            from faster_whisper import WhisperModel

            last_err: Exception | None = None
            for name, dev, index, compute in self._candidates(model_name, device, need):
                try:
                    log(f"loading whisper '{name}' on {dev}:{index} ({compute}, {THREADS} threads)")
                    model = WhisperModel(name, device=dev, device_index=index, compute_type=compute, cpu_threads=THREADS)
                    # CUDA problems (missing cuDNN/cuBLAS) only surface on first use.
                    list(model.transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32))[0])
                    self.model, self.config = model, (model_name, device, need)
                    self.active_device, self.active_model = dev, name
                    log(f"whisper '{name}' ready on {dev}")
                    return
                except Exception as e:  # noqa: BLE001
                    log(f"whisper '{name}' on {dev} failed: {e}")
                    last_err = e
            raise RuntimeError(f"could not load speech model: {last_err}")

    def _unload(self) -> None:
        if self.model is not None:
            self.model = None
            self.config = None
            self.active_device = self.active_model = "none"
            gc.collect()

    def unload(self) -> None:
        with self._lock:
            self._unload()

    @property
    def loaded(self) -> bool:
        return self.model is not None

    def transcribe(
        self,
        audio: np.ndarray,
        language: str | None,
        vocabulary: str | None = None,
        on_progress: Callable[[float], None] | None = None,
        vad: bool = True,
        words: bool | str = False,
        languages: list[str] | None = None,
        translate: bool | list[str] = False,
        prefer: str | None = None,
        live: bool = False,
        cuts: list[float] | None = None,
    ) -> list[dict]:
        """`vocabulary` ("Jarvis, Priya, Voice Desk") is given as Whisper's initial
        prompt. Tested: this fixes names ("Nishchay" instead of "in Eshchai"),
        while `hotwords` and previous-text context made short commands worse.

        `languages` (e.g. ["en", "hi", "gu"]): the language is detected among
        these. Long recordings are split at pauses and each part detected on its
        own, so a meeting can switch languages. `translate` turns non-English
        speech into English text. `cuts`: times (s) where the speaker changes;
        Hindi/Gujarati chunks are cut there so no line holds two people."""
        model = self.model
        if model is None:
            raise RuntimeError("speech model not loaded")
        if languages and len(languages) > 1 and len(audio) > 30 * SAMPLE_RATE:
            segs = self._transcribe_parts(audio, vocabulary, on_progress, words, languages, translate, prefer, cuts)
            return segs if cuts is not None else [untimed(s) for s in segs]
        if languages and len(languages) > 1:
            language = self.pick_language(audio, languages, prefer)
        elif languages:
            language = languages[0]
        task = task_for(language, translate)
        choices = [c for c in languages or [] if c in indic.LANGS and task_for(c, translate) == "transcribe"]
        segs = self._transcribe(audio, language, vocabulary, on_progress, vad, exact_words(words, language, task), task, live, choices, cuts)
        for seg in segs:
            seg.setdefault("lang", language)
            if words and "words" not in seg:
                seg["words"] = spread_words(seg["text"], seg["start"], seg["end"])
        # "timed" (measured word times) is only for splitting lines by speaker.
        return segs if cuts is not None else [untimed(s) for s in segs]

    def pick_language(self, audio: np.ndarray, allowed: list[str], prefer: str | None = None) -> str:
        """Language of this phrase, among the ones the user speaks.

        Whisper tells English from Indian languages reliably, but not Hindi from
        Gujarati: on the user's own Gujarati it answered "Hindi" with ~0.9 and
        Gujarati ~0.0, then effectively translated the speech into Hindi. So it
        only decides English vs Indian language; which Indian language is the
        user's choice (`prefer`) when they speak more than one."""
        _, _, probs = self.model.detect_language(audio)
        p = dict(probs)
        indic_allowed = [code for code in allowed if code != "en"]
        if "en" in allowed:
            p_indic = sum(v for k, v in p.items() if k in INDIC)
            if not indic_allowed or p.get("en", 0.0) >= p_indic:
                return "en"
        if len(indic_allowed) == 1:
            return indic_allowed[0]
        if prefer in indic_allowed:
            return prefer
        return max(indic_allowed, key=lambda code: p.get(code, 0.0))

    def _transcribe_parts(self, audio, vocabulary, on_progress, words, languages, translate, prefer, cuts=None) -> list[dict]:
        spans = speech_spans(audio, min_silence_ms=700, pad_ms=200)
        out: list[dict] = []
        for i, sp in enumerate(spans):
            part = audio[sp["start"] : sp["end"]]
            offset = sp["start"] / SAMPLE_RATE
            lang = self.pick_language(part, languages, prefer)
            choices = [c for c in languages if c in indic.LANGS and task_for(c, translate) == "transcribe"]
            task = task_for(lang, translate)
            part_cuts = [c - offset for c in cuts or [] if 0 < c - offset < len(part) / SAMPLE_RATE]
            for seg in self._transcribe(part, lang, vocabulary, None, False, exact_words(words, lang, task), task,
                                        choices=choices, cuts=part_cuts):
                seg.setdefault("lang", lang)
                if words and "words" not in seg:
                    seg["words"] = spread_words(seg["text"], seg["start"], seg["end"])
                seg["start"] = round(seg["start"] + offset, 2)
                seg["end"] = round(seg["end"] + offset, 2)
                for w in seg.get("words", []):
                    w["s"] = round(w["s"] + offset, 2)
                    w["e"] = round(w["e"] + offset, 2)
                out.append(seg)
            if on_progress:
                on_progress((i + 1) / len(spans))
        return out

    def _transcribe(self, audio, language, vocabulary, on_progress, vad, words, task, live=False, choices=None, cuts=None) -> list[dict]:
        model = self.model
        if model is None:
            raise RuntimeError("speech model not loaded")
        self.last_used = time.time()
        if task == "transcribe" and language in indic.LANGS and indic_asr.load():
            return self._transcribe_indic(audio, language, on_progress, vad, words, choices, cuts)
        segments, info = model.transcribe(
            audio,
            language=language or None,
            task=task,
            beam_size=5,
            vad_filter=vad,
            vad_parameters={"min_silence_duration_ms": 500},
            initial_prompt=(vocabulary.strip().rstrip(".") + ".") if vocabulary and vocabulary.strip() else None,
            condition_on_previous_text=False,
            word_timestamps=words,
            # Live: at most one retry when Whisper is unsure. The default ladder of
            # six temperatures made a single unclear phrase take 5-8 s.
            temperature=(0.0, 0.4) if live else (0.0, 0.2, 0.4, 0.6, 0.8, 1.0),
        )
        out = []
        for s in segments:
            text = s.text.strip()
            if on_progress and info.duration:
                on_progress(min(1.0, s.end / info.duration))
            if not text:
                continue
            # Drop likely hallucinations: repetitive loops, or stock phrases Whisper
            # emits over noise when it isn't really sure anything was said.
            if s.compression_ratio > 2.4:
                continue
            text = collapse_repeats(text)
            if text.lower() in HALLUCINATIONS and (s.no_speech_prob > 0.3 or s.avg_logprob < -0.7):
                continue
            if s.no_speech_prob > 0.7 and s.avg_logprob < -1.0:
                continue
            clip = audio[int(s.start * SAMPLE_RATE) : int(s.end * SAMPLE_RATE)]
            if vad and not is_real_speech(clip):
                continue  # background noise turned into text
            seg = {"start": round(s.start, 2), "end": round(s.end, 2), "text": text}
            if words:
                seg["words"] = [
                    {"w": w.word.strip(), "s": round(w.start, 2), "e": round(w.end, 2)} for w in (s.words or []) if w.word.strip()
                ]
                seg["timed"] = True  # measured word times, not estimated
            out.append(seg)
        self.last_used = time.time()
        return out


    def _transcribe_indic(self, audio, language, on_progress, vad, words, choices=None, cuts=None) -> list[dict]:
        """Hindi/Gujarati in their own script via IndicConformer, in chunks of up to
        12 s cut at pauses (see `indic_chunks`) and where the speaker changes
        (`cuts`). It gives no word timings, so they are estimated. `choices`:
        Indian languages to pick between (Hindi/Gujarati)."""
        chunks = cut_chunks(indic_chunks(audio, vad), cuts)
        out = []
        for i, (start, end) in enumerate(chunks):
            clip = audio[start:end]
            if vad and not is_real_speech(clip):
                continue
            text, lang = indic_asr.transcribe(clip, language, choices)
            text = collapse_repeats(text)
            if on_progress:
                on_progress((i + 1) / len(chunks))
            if not text:
                continue
            seg = {"start": round(start / SAMPLE_RATE, 2), "end": round(end / SAMPLE_RATE, 2), "text": text, "lang": lang}
            if words:
                seg["words"] = spread_words(text, seg["start"], seg["end"])
            out.append(seg)
        self.last_used = time.time()
        return out


def cut_chunks(chunks: list[tuple[int, int]], cuts: list[float] | None, min_s: float = 0.3) -> list[tuple[int, int]]:
    """Split sample ranges at the given times (s), keeping pieces >= min_s.
    IndicConformer reads short pieces well (a 1 s question came out right)."""
    if not cuts:
        return chunks
    min_n = int(min_s * SAMPLE_RATE)
    out = []
    for start, end in chunks:
        at = start
        for c in sorted(int(c * SAMPLE_RATE) for c in cuts):
            if at + min_n <= c <= end - min_n:
                out.append((at, c))
                at = c
        out.append((at, end))
    return out


def indic_chunks(audio: np.ndarray, vad: bool = True) -> list[tuple[int, int]]:
    """Cut audio into pieces IndicConformer decodes reliably (<= indic.MAX_CHUNK_S).

    Stretches of speech are joined while they fit; a longer stretch is cut at
    its shorter pauses (breaths), and only as a last resort mid-speech. Tested:
    decoding each short stretch alone lost words, and long inputs lost the start.
    Without `vad` (live dictation) silence is kept, but long phrases still split."""
    limit = indic.MAX_CHUNK_S * SAMPLE_RATE

    def pieces(start: int, end: int, silence_ms: int) -> list[tuple[int, int]]:
        spans = speech_spans(audio[start:end], min_silence_ms=silence_ms, pad_ms=100)
        if not spans:
            return [] if vad else [(x, min(x + limit, end)) for x in range(start, end, limit)]
        out: list[list[int]] = []
        for sp in spans:
            a, b = start + sp["start"], start + sp["end"]
            if out and b - out[-1][0] <= limit:
                out[-1][1] = b
            else:
                out.append([a, b])
        result: list[tuple[int, int]] = []
        for a, b in out:
            if b - a <= limit:
                result.append((a, b))
            elif silence_ms > 150:
                result += pieces(a, b, 150)
            else:
                result += [(x, min(x + limit, b)) for x in range(a, b, limit)]
        return result

    if not vad and len(audio) <= limit:
        return [(0, len(audio))]
    return pieces(0, len(audio), 500)


def preload_indic(languages: list[str] | None, translate, hf_token: str | None) -> None:
    """Load IndicConformer ahead of the first Hindi/Gujarati phrase (~20 s) when
    those languages are written in their own script."""
    if indic.wanted(languages, translate) and not indic_asr.loaded:
        indic_asr.load(hf_token)


transcriber = Transcriber()
voiceprint = VoicePrint()
VOICE_THRESHOLD = 0.30  # cosine similarity; the user's voice scores ~0.35-0.6, others < 0.2


def load_profile(path: str | None) -> np.ndarray | None:
    if path and os.path.exists(path):
        return np.load(path)
    return None


def voice_score(profile: np.ndarray, audio: np.ndarray) -> float | None:
    speech = speech_only(audio)
    if len(speech) < SAMPLE_RATE // 2:
        return None  # too little speech to judge
    return round(VoicePrint.similarity(profile, voiceprint.embed(speech)), 3)


# --------------------------------------------------------------------------- #
# Live dictation stream
# --------------------------------------------------------------------------- #


class Stream:
    """Receives live mic audio, cuts it into utterances at pauses, and emits
    each utterance's text (with voice commands split out) as soon as it ends."""

    STEP_S = 0.2  # how often to look for a finished utterance
    MAX_UTTERANCE_S = 15.0  # force a cut in long monologues to keep latency low

    def __init__(self, sid: int, opts: dict) -> None:
        self.sid = sid
        self.opts = opts
        self.silence_ms = int(opts.get("silence_ms") or 700)
        self.profile = load_profile(opts.get("voice_profile"))
        self.buf = np.zeros(0, np.float32)
        self.buf_start = 0  # absolute sample index of buf[0] since stream start
        self.pending: list[np.ndarray] = []
        self.cond = threading.Condition()
        self.stopping = False
        self.done = threading.Event()
        self.thread = threading.Thread(target=self.run, name=f"stream-{sid}", daemon=True)
        self.thread.start()

    def feed(self, pcm: bytes) -> None:
        a = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
        with self.cond:
            self.pending.append(a)
            self.cond.notify()

    def update(self, opts: dict) -> None:
        self.opts.update(opts)
        if "voice_profile" in opts:
            self.profile = load_profile(opts.get("voice_profile"))

    def stop(self) -> None:
        with self.cond:
            self.stopping = True
            self.cond.notify()
        self.done.wait(timeout=120)

    def run(self) -> None:
        try:
            o = self.opts
            transcriber.load(o.get("model", "auto"), o.get("device", "auto"), o.get("languages"), o.get("translate") or False)
            threading.Thread(
                target=preload_indic, args=(o.get("languages"), o.get("translate"), o.get("hf_token")), daemon=True
            ).start()
            send({"event": "stream_ready", "sid": self.sid, "device": transcriber.active_device,
                  "model": transcriber.active_model})
            unchecked = 0
            while True:
                with self.cond:
                    while not self.pending and not self.stopping:
                        self.cond.wait(0.5)
                    chunks, self.pending = self.pending, []
                    final = self.stopping
                if chunks:
                    new = np.concatenate(chunks)
                    unchecked += len(new)
                    self.buf = np.concatenate([self.buf, new])
                if final or unchecked >= self.STEP_S * SAMPLE_RATE:
                    unchecked = 0
                    self.step(final)
                if final:
                    break
        except Exception as e:  # noqa: BLE001
            log(traceback.format_exc())
            send({"event": "stream_error", "sid": self.sid, "message": str(e)})
        finally:
            self.done.set()

    def _consume(self, upto: int) -> None:
        self.buf = self.buf[upto:]
        self.buf_start += upto

    def step(self, final: bool) -> None:
        sr = SAMPLE_RATE
        pad = int(0.15 * sr)
        spans = speech_spans(self.buf, min_silence_ms=self.silence_ms, pad_ms=150)
        if not spans:
            # Nothing said yet: keep only the last second so a word onset isn't lost.
            if len(self.buf) > sr:
                self._consume(len(self.buf) - sr)
            return

        # Spans are separated by >= silence_ms, so every span except the last is
        # complete; the last one is complete once enough silence follows it.
        silence = int(self.silence_ms * sr / 1000)
        last = spans[-1]
        last_closed = final or (last["end"] - pad + silence <= len(self.buf))
        closed = spans if last_closed else spans[:-1]
        if closed:
            start, end = closed[0]["start"], closed[-1]["end"]
            self.emit(self.buf[start:end], self.buf_start + start)
            self._consume(end)
            return

        # One long open utterance: cut at a short breath pause if it gets too long.
        start = last["start"]
        if len(self.buf) - start > self.MAX_UTTERANCE_S * sr:
            fine = speech_spans(self.buf[start:], min_silence_ms=150, pad_ms=50)
            cut = None
            for s in fine:
                end = start + s["end"]
                if start + 3 * sr < end < len(self.buf) - sr // 2:
                    cut = end
            cut = cut or len(self.buf)
            self.emit(self.buf[start:cut], self.buf_start + start)
            self._consume(cut)
        elif start > sr:
            self._consume(start - pad if start > pad else 0)

    def emit(self, audio: np.ndarray, abs_start: int) -> None:
        o = self.opts
        if not is_real_speech(audio):
            log(f"ignored {len(audio) / SAMPLE_RATE:.1f}s of background noise")
            return
        vocab = o.get("vocabulary")
        langs, translate, prefer = o.get("languages") or None, o.get("translate") or False, o.get("prefer")
        segs = transcriber.transcribe(
            audio, o.get("language"), vocab, vad=False, words="auto", languages=langs, translate=translate, prefer=prefer, live=True
        )
        lang = segs[0].get("lang") if segs else None
        text = " ".join(s["text"] for s in segs).strip()
        if echoes_vocabulary(text, vocab):
            # Decode again without the hint; keep it only if real words remain.
            segs = transcriber.transcribe(audio, lang or o.get("language"), None, vad=False, words="auto", translate=translate, live=True)
            retry = " ".join(s["text"] for s in segs).strip()
            log(f"prompt echo {text!r} -> {retry!r}")
            text = "" if retry.lower() in HALLUCINATIONS or echoes_vocabulary(retry, vocab) else retry
        if not text:
            return
        wake, cmds = o.get("wake_name") or "", o.get("commands") or {}
        parts = commands.parse(text, wake, cmds)
        if wake and len(audio) < 4 * SAMPLE_RATE and commands.is_bare_command(text, cmds):
            # "Jarvis, resume" sometimes loses the name ("Resume"). A bare command
            # word on its own is suspicious, so decode once more without hints.
            retry = transcriber.transcribe(audio, lang or o.get("language"), None, vad=False, words=True, live=True)
            retry_text = " ".join(s["text"] for s in retry).strip()
            retry_parts = commands.parse(retry_text, wake, cmds)
            if any(p["type"] == "command" for p in retry_parts):
                log(f"recovered command: {text!r} -> {retry_text!r}")
                segs, text, parts = retry, retry_text, retry_parts
        if wake and lang and lang != "en" and len(audio) < 2.0 * SAMPLE_RATE and not any(p["type"] == "command" for p in parts):
            # Commands are English words; an accent can make "Jarvis, pause" look
            # like Hindi/Gujarati. Short phrases get a second, English-only read.
            retry = transcriber.transcribe(audio, "en", o.get("vocabulary"), vad=False, words=True, live=True)
            retry_text = " ".join(s["text"] for s in retry).strip()
            retry_parts = commands.parse(retry_text, wake, cmds)
            if any(p["type"] == "command" for p in retry_parts):
                log(f"command heard in English: {text!r} -> {retry_text!r}")
                segs, text, parts = retry, retry_text, retry_parts
        attach_words(text, [w for s in segs for w in s["words"]], parts, abs_start / SAMPLE_RATE)
        score = voice_score(self.profile, audio) if self.profile is not None else None
        send({
            "event": "utterance",
            "sid": self.sid,
            "start": round(abs_start / SAMPLE_RATE, 2),
            "end": round((abs_start + len(audio)) / SAMPLE_RATE, 2),
            "text": text,
            "parts": parts,
            "score": score,
            "lang": lang,
        })


def attach_words(text: str, words: list[dict], parts: list[dict], offset: float) -> None:
    """Give each text part its words with stream-relative times (for playback
    highlighting). Words are located in `text` in order; command words are dropped."""
    located = []
    cursor = 0
    for w in words:
        i = text.find(w["w"], cursor)
        if i < 0:
            continue
        cursor = i + len(w["w"])
        located.append((i, {"w": w["w"], "s": round(w["s"] + offset, 2), "e": round(w["e"] + offset, 2)}))
    for part in parts:
        if part["type"] == "text":
            a, b = part["span"]
            part["words"] = [w for i, w in located if a <= i < b]
        part.pop("span", None)


streams: dict[int, Stream] = {}
streams_lock = threading.Lock()


def cmd_stream_start(req: dict) -> dict:
    sid = int(req["sid"])
    with streams_lock:
        if sid in streams:
            return {"sid": sid}
        streams[sid] = Stream(sid, dict(req))
    return {"sid": sid}


def cmd_stream_update(req: dict) -> dict:
    s = streams.get(int(req["sid"]))
    if s:
        s.update({k: v for k, v in req.items() if k not in ("id", "cmd", "sid")})
    return {}


def cmd_stream_stop(req: dict) -> dict:
    sid = int(req["sid"])
    with streams_lock:
        s = streams.pop(sid, None)
    if s:
        s.stop()  # flushes the last utterance before replying
    return {"sid": sid}


def on_audio(req: dict) -> None:
    s = streams.get(int(req.get("sid", -1)))
    if s:
        s.feed(base64.b64decode(req["pcm"]))


# --------------------------------------------------------------------------- #
# Diarization (subprocess) and meetings
# --------------------------------------------------------------------------- #


def diarize(audio: np.ndarray, hf_token: str | None, num_speakers: int | None, device: str = "auto") -> list[tuple[float, float, str]]:
    """Run diarize.py in a child process so torch's memory is released afterwards.
    It runs where the Processor setting says: the CPU, or that GPU."""
    fd, path = tempfile.mkstemp(suffix=".wav", prefix="voicedesk-diar-")
    os.close(fd)
    try:
        write_wav(path, audio)
        env = dict(os.environ)
        if hf_token:
            env["HF_TOKEN"] = hf_token
        kind, index = parse_device(device)
        env["VOICEDESK_DEVICE"] = kind
        if kind == "cpu":
            env["CUDA_VISIBLE_DEVICES"] = "-1"
        elif kind == "cuda":
            env["CUDA_VISIBLE_DEVICES"] = str(index)
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "diarize.py")
        flags = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW
        proc = subprocess.run(
            [sys.executable, script, path, str(num_speakers or 0)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env, creationflags=flags, timeout=3 * 3600,
        )
        for line in proc.stderr.splitlines()[-5:]:
            log("diarize:", line)
        try:
            result = json.loads(proc.stdout.strip().splitlines()[-1])
        except (json.JSONDecodeError, IndexError):
            raise RuntimeError(f"speaker detection crashed (exit {proc.returncode})") from None
        if "error" in result:
            raise RuntimeError(result["error"])
        return [(t[0], t[1], t[2]) for t in result["turns"]]
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


# Speaker turns shorter than this are noise in the diarization (seen: 0.02-0.05 s blips).
MIN_TURN_S = 0.25
# The same person continuing after a pause this short stays one line.
JOIN_GAP_S = 1.0
def speaker_pieces(turns: list[tuple[float, float, str]]) -> list[tuple[float, float, str]]:
    """Who spoke when, cleaned up for transcription: blips dropped, and one
    person's back-to-back turns joined."""
    out: list[list] = []
    for a, b, spk in sorted(t for t in turns if t[1] - t[0] >= MIN_TURN_S):
        if out and out[-1][2] == spk and a - out[-1][1] <= JOIN_GAP_S:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b, spk])
    return [(a, b, spk) for a, b, spk in out]


def speaker_changes(pieces: list[tuple[float, float, str]]) -> list[float]:
    """Times where one person stops and another starts (middle of the gap)."""
    return [round((a[1] + b[0]) / 2, 2) for a, b in zip(pieces, pieces[1:]) if a[2] != b[2]]


def speaker_at(t: float, pieces: list[tuple[float, float, str]]) -> str:
    """Who was speaking at time t (the nearest turn when it falls in a gap)."""
    for a, b, spk in pieces:
        if a <= t <= b:
            return spk
    return min(pieces, key=lambda p: min(abs(t - p[0]), abs(t - p[1])))[2]


def split_by_speaker(segments: list[dict], pieces: list[tuple[float, float, str]]) -> list[dict]:
    """Give every line one speaker, splitting lines where the speaker changes.

    Whisper's lines get split word by word (its word times are measured); one
    stray word between two of the same speaker's stays with them. Lines with
    estimated word times (Hindi/Gujarati, already cut at speaker changes) take
    the speaker who covers most of the line.

    Measured on a real 3-person call, labelling whole lines put 4 of 9 lines
    across two speakers (8% of words on the wrong person); Hindi/Gujarati
    chunks of up to 12 s often held a question and its answer. Transcribing
    each turn on its own instead lost short replies ("No.") - Whisper needs the
    surrounding audio."""
    out: list[dict] = []
    for seg in segments:
        words = seg.get("words") or []
        if not seg.pop("timed", False) or len(words) < 2:
            overlap: dict[str, float] = {}
            for a, b, spk in pieces:
                o = min(seg["end"], b) - max(seg["start"], a)
                if o > 0:
                    overlap[spk] = overlap.get(spk, 0.0) + o
            seg["speaker"] = max(overlap, key=overlap.get) if overlap else speaker_at((seg["start"] + seg["end"]) / 2, pieces)
            out.append(seg)
            continue
        who = [speaker_at((w["s"] + w["e"]) / 2, pieces) for w in words]
        for k in range(1, len(who) - 1):
            if who[k - 1] == who[k + 1] != who[k]:
                who[k] = who[k - 1]
        start = 0
        for k in range(1, len(words) + 1):
            if k == len(words) or who[k] != who[start]:
                part = words[start:k]
                out.append({**seg, "start": part[0]["s"], "end": part[-1]["e"], "speaker": who[start],
                            "text": " ".join(w["w"] for w in part), "words": part})
                start = k
    return out


def transcribe_with_speakers(audio: np.ndarray, turns, tx, on_progress=None) -> list[dict]:
    """Transcribe the whole recording once (Whisper needs the context), cutting
    Hindi/Gujarati chunks where the speaker changes, then split lines by speaker."""
    pieces = speaker_pieces(turns)
    if not pieces:
        return []
    segs = tx(audio, on_progress, cuts=speaker_changes(pieces))
    return split_by_speaker(segs, pieces)

def label_me(segments: list[dict], audio: np.ndarray, profile: np.ndarray) -> None:
    """In a single-track (in-person) recording, find which speaker is the user by voice."""
    by_speaker: dict[str, list[np.ndarray]] = {}
    for s in segments:
        clip = audio[int(s["start"] * SAMPLE_RATE) : int(s["end"] * SAMPLE_RATE)]
        by_speaker.setdefault(s["speaker"], []).append(clip)
    best, best_score = None, VOICE_THRESHOLD
    for spk, clips in by_speaker.items():
        joined = np.concatenate(clips)[: 30 * SAMPLE_RATE]
        score = voice_score(profile, joined)
        log(f"voice match {spk}: {score}")
        if score is not None and score >= best_score:
            best, best_score = spk, score
    if best is not None:
        for s in segments:
            if s["speaker"] == best:
                s["speaker"] = "Me"


def friendly_speaker_names(segments: list[dict]) -> None:
    """SPEAKER_00 -> Speaker 1, in order of first appearance. 'Me'/'Others' are kept."""
    mapping: dict[str, str] = {}
    for seg in segments:
        spk = seg["speaker"]
        if spk in ("Me", "Others"):
            continue
        if spk not in mapping:
            mapping[spk] = f"Speaker {len(mapping) + 1}"
        seg["speaker"] = mapping[spk]


def cmd_meeting(req: dict) -> dict:
    """Transcribe + diarize a meeting.

    mic_path     : the user's microphone -> labelled "Me".
    mic_segments : already-transcribed mic utterances (live task capture) -> "Me", skips mic_path.
    system_path  : speaker/headphone loopback (remote participants) -> diarized.
    With no usable system audio (in-person meeting) the mic track is diarized
    instead, and the user's voice profile (if any) decides which speaker is "Me".
    """
    rid = req["id"]

    def progress(stage: str, pct: float) -> None:
        send({"id": rid, "event": "progress", "stage": stage, "pct": round(pct)})

    def warn(message: str) -> None:
        send({"id": rid, "event": "warning", "message": message})

    progress("Loading speech model", 0)
    langs, translate, prefer = req.get("languages") or None, req.get("translate") or False, req.get("prefer")
    transcriber.load(req.get("model", "auto"), req.get("device", "auto"), langs, translate)
    preload_indic(langs, translate, req.get("hf_token"))
    language, vocab = req.get("language"), req.get("vocabulary")

    def tx(audio: np.ndarray, on_progress=None, cuts=None) -> list[dict]:
        return transcriber.transcribe(
            audio, language, vocab, on_progress=on_progress, words="auto", languages=langs, translate=translate,
            prefer=prefer, cuts=cuts,
        )
    profile = load_profile(req.get("voice_profile"))
    hf_token, num_speakers = req.get("hf_token"), req.get("num_speakers")

    mic = read_wav(req["mic_path"]) if req.get("mic_path") and os.path.exists(req["mic_path"]) else np.zeros(0, np.float32)
    system = read_wav(req["system_path"]) if req.get("system_path") and os.path.exists(req["system_path"]) else np.zeros(0, np.float32)
    mic_segments = req.get("mic_segments")
    progress("Checking audio", 2)
    has_system = speech_seconds(system) >= 2.0
    has_mic = mic_segments is not None or speech_seconds(mic) >= 0.5
    log(f"meeting: mic {len(mic) / SAMPLE_RATE:.0f}s (speech={has_mic}), "
        f"system {len(system) / SAMPLE_RATE:.0f}s (speech={has_system})")

    segments: list[dict] = []
    if mic_segments is not None:
        segments += [
            {"start": s["start"], "end": s["end"], "text": s["text"], "speaker": "Me", "words": s.get("words")}
            for s in mic_segments
        ]
    elif has_mic:
        if has_system:
            progress("Transcribing your microphone", 5)
            mic_segs = tx(mic, lambda f: progress("Transcribing your microphone", 5 + f * 35))
            for s in mic_segs:
                s["speaker"] = "Me"
            segments += mic_segs
        else:
            # In-person meeting: everyone is on the mic. Find who speaks when,
            # transcribe each turn, then find the user by voice.
            progress("Identifying speakers", 5)
            try:
                turns = diarize(mic, hf_token, num_speakers, req.get("device", "auto"))
            except Exception as e:  # noqa: BLE001
                warn(f"Speaker detection skipped: {e}")
                turns = []
            if turns:
                progress("Transcribing", 40)
                mic_segs = transcribe_with_speakers(mic, turns, tx, lambda f: progress("Transcribing", 40 + f * 55))
            else:
                progress("Transcribing your microphone", 40)
                mic_segs = tx(mic, lambda f: progress("Transcribing your microphone", 40 + f * 55))
                for s in mic_segs:
                    s["speaker"] = "Speaker"
            if profile is not None:
                if all(s["speaker"] == "Speaker" for s in mic_segs):
                    for s in mic_segs:  # no diarization: judge each segment by voice
                        clip = mic[int(s["start"] * SAMPLE_RATE) : int(s["end"] * SAMPLE_RATE)]
                        score = voice_score(profile, clip)
                        s["speaker"] = "Me" if score is not None and score >= VOICE_THRESHOLD else "Others"
                else:
                    label_me(mic_segs, mic, profile)
            segments += mic_segs

    if has_system:
        # Everyone else in the call: find who speaks when, then transcribe each turn.
        progress("Identifying speakers", 40)
        try:
            turns = diarize(system, hf_token, num_speakers, req.get("device", "auto"))
        except Exception as e:  # noqa: BLE001
            warn(f"Speaker detection skipped: {e}")
            turns = []
        if turns:
            progress("Transcribing meeting audio", 65)
            sys_segs = transcribe_with_speakers(system, turns, tx, lambda f: progress("Transcribing meeting audio", 65 + f * 33))
        else:
            progress("Transcribing meeting audio", 65)
            sys_segs = tx(system, lambda f: progress("Transcribing meeting audio", 65 + f * 33))
            for s in sys_segs:
                s["speaker"] = "Others"
        segments += sys_segs

    segments.sort(key=lambda s: s["start"])
    friendly_speaker_names(segments)
    progress("Transcript ready", 100)
    duration = max(len(mic), len(system)) / SAMPLE_RATE
    if mic_segments:
        duration = max(duration, max(s["end"] for s in mic_segments))
    return {"segments": segments, "duration": round(duration, 1), "others_spoke": has_system}


# --------------------------------------------------------------------------- #
# Other commands
# --------------------------------------------------------------------------- #


def cmd_load(req: dict) -> dict:
    transcriber.load(req.get("model", "auto"), req.get("device", "auto"), req.get("languages"), req.get("translate") or False)
    return {"device": transcriber.active_device, "model": transcriber.active_model}


def cmd_transcribe(req: dict) -> dict:
    transcriber.load(req.get("model", "auto"), req.get("device", "auto"), req.get("languages"), req.get("translate") or False)
    audio = read_wav(req["path"])
    segments = transcriber.transcribe(
        audio, req.get("language"), req.get("vocabulary"), languages=req.get("languages"), translate=req.get("translate") or False
    )
    return {"text": " ".join(s["text"] for s in segments).strip(), "segments": segments}


def cmd_enroll(req: dict) -> dict:
    """Build the user's voice profile from a recording of them reading aloud."""
    audio = speech_only(read_wav(req["path"]))
    seconds = len(audio) / SAMPLE_RATE
    if seconds < 6:
        raise ValueError(f"Only {seconds:.0f}s of speech was heard. Please read the text aloud for about 15 seconds.")
    win, hop = 3 * SAMPLE_RATE, int(1.5 * SAMPLE_RATE)
    embs = [voiceprint.embed(audio[i : i + win]) for i in range(0, len(audio) - win + 1, hop)]
    profile = np.mean(embs, axis=0)
    profile /= np.linalg.norm(profile)
    consistency = float(np.mean([VoicePrint.similarity(profile, e) for e in embs]))
    np.save(req["out"], profile)
    return {"seconds": round(seconds, 1), "consistency": round(consistency, 2)}


def cmd_configure(req: dict) -> dict:
    global idle_unload_s
    idle_unload_s = max(0, int(req.get("unload_after_min", 10))) * 60
    return {}


def cmd_status(req: dict) -> dict:
    return {"loaded": transcriber.loaded, "device": transcriber.active_device, "model": transcriber.active_model}


COMMANDS: dict[str, Callable[[dict], dict]] = {
    "ping": lambda req: {"pong": True},
    "load": cmd_load,
    "unload": lambda req: (transcriber.unload(), indic_asr.unload(), voiceprint.unload(), {})[-1],
    "configure": cmd_configure,
    "status": cmd_status,
    "transcribe": cmd_transcribe,
    "stream_start": cmd_stream_start,
    "stream_update": cmd_stream_update,
    "stream_stop": cmd_stream_stop,
    "meeting": cmd_meeting,
    "enroll": cmd_enroll,
}

idle_unload_s = 10 * 60


def gpu_keepalive() -> None:
    """While listening, give the GPU a tiny job (16 ms) every second.

    Laptop GPUs drop to power-saving clocks after a few idle seconds and ramp
    up slowly; measured here, a phrase after a 6 s pause took 3.7-5.3 s instead
    of 1.5 s. The keepalive costs ~1.6% of the GPU and keeps it at 1.8 s.
    """
    import ctranslate2

    tiny = None
    while True:
        time.sleep(1.0)
        model = transcriber.model
        if not streams or model is None or transcriber.active_device != "cuda":
            continue
        try:
            if tiny is None:
                mels = model.model.n_mels  # 128 for large-v3, 80 for older models
                tiny = ctranslate2.StorageView.from_array(np.zeros((1, mels, 100), np.float32))
            model.model.encode(tiny, to_cpu=False)
        except Exception as e:  # noqa: BLE001 — never let this break dictation
            log(f"gpu keepalive: {e}")
            tiny = None


def idle_watchdog() -> None:
    """Free all memory when Voice Desk hasn't been used for a while.

    Unloading the model alone keeps ~750 MB of CUDA libraries mapped, so the
    whole process exits instead; the app restarts it on the next request.
    """
    while True:
        time.sleep(30)
        if idle_unload_s and transcriber.loaded and not streams and time.time() - transcriber.last_used > idle_unload_s:
            log("idle: exiting to free memory")
            send({"event": "sleeping"})
            os._exit(0)


def handle(req: dict) -> None:
    rid = req.get("id")
    try:
        fn = COMMANDS.get(req.get("cmd", ""))
        if fn is None:
            raise ValueError(f"unknown command: {req.get('cmd')}")
        send({"id": rid, "ok": True, "result": fn(req)})
    except Exception as e:  # noqa: BLE001
        log(traceback.format_exc())
        send({"id": rid, "ok": False, "error": str(e)})


def isolate_protocol_pipes() -> None:
    """Keep the JSON protocol on private copies of the original stdin/stdout.

    - Libraries that print() would otherwise corrupt the protocol, so fd 1 is
      pointed at stderr.
    - On Windows, a thread that touches the stdin handle (GetFileType, spawning a
      subprocess, ...) while the main thread is blocked reading it deadlocks.
      fd 0 is pointed at the null device instead.
    """
    global _proto_in, _proto_out
    _proto_in = os.fdopen(os.dup(0), "r", encoding="utf-8", newline="\n")
    _proto_out = os.fdopen(os.dup(1), "w", encoding="utf-8", newline="\n")
    devnull = os.open(os.devnull, os.O_RDONLY)
    os.dup2(devnull, 0)
    os.close(devnull)
    os.dup2(2, 1)
    sys.stdin = open(os.devnull, encoding="utf-8")
    sys.stdout = sys.stderr


def prefetch() -> None:
    """Download models ahead of time so the first run starts instantly."""
    import ctranslate2
    from faster_whisper import download_model
    from huggingface_hub import hf_hub_download

    import voiceprint as vp

    names = ["large-v3-turbo", "small"] if ctranslate2.get_cuda_device_count() > 0 else ["small"]
    for name in names:
        print(f"Downloading speech model '{name}'...", flush=True)
        download_model(name)
    print("Downloading voice-ID model...", flush=True)
    hf_hub_download(vp.REPO, vp.FILENAME)
    print("Checking the speech model loads...", flush=True)
    transcriber.load()
    print(f"OK: '{transcriber.active_model}' runs on {transcriber.active_device}.", flush=True)


def main() -> None:
    if "--prefetch" in sys.argv:
        prefetch()
        return
    isolate_protocol_pipes()
    threading.Thread(target=idle_watchdog, daemon=True).start()
    threading.Thread(target=gpu_keepalive, daemon=True).start()
    log("ready")
    send({"event": "ready"})
    # Each request runs on its own thread so dictation never waits behind a long
    # meeting job. Live audio chunks are handled inline to keep their order.
    for line in _proto_in:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            log(f"bad request: {e}")
            continue
        if req.get("cmd") == "audio":
            on_audio(req)
            continue
        threading.Thread(target=handle, args=(req,), daemon=True).start()
    # stdin closed: the app exited.
    os._exit(0)


if __name__ == "__main__":
    main()
