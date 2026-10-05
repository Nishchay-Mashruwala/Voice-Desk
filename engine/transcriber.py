"""Whisper (faster-whisper) and IndicConformer: which model on which device,
and turning audio into timed text."""

from __future__ import annotations

import gc
import os
import subprocess
import threading
import time
from typing import Callable

import numpy as np

from indic import indic_asr, uncovered
from mixed import join_words, merge
from runtime import SAMPLE_RATE, THREADS, hub_snapshot, log
from speech import collapse_repeats, echoes_vocabulary, is_real_speech, speech_spans
import indic

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
# runtime on an RTX 3050 (2026-10-05): large-v3 2.3, turbo 1.27, medium 1.24,
# small 0.49 GB. base/tiny scaled by model size. Settings shows the same (src/models.ts).
GPU_NEED_GB = {"large-v3": 2.3, "large-v3-turbo": 1.2, "medium": 1.2, "small": 0.6, "base": 0.4, "tiny": 0.3}
# Models the CPU runs at a usable speed; bigger choices fall back to `cpu_model()` there.
CPU_MODELS = {"small", "base", "tiny"}
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


def cuda_usable() -> bool:
    """An NVIDIA GPU *and* the CUDA libraries Whisper needs (the NVIDIA pack).
    With a GPU but without the libraries, trying the GPU first would download a
    GPU-sized model (~1.6 GB) that then can't run."""
    import site

    try:
        import ctranslate2

        if ctranslate2.get_cuda_device_count() == 0:
            return False
    except Exception:  # noqa: BLE001
        return False
    dirs = site.getsitepackages() + [site.getusersitepackages()]
    return any(os.path.isdir(os.path.join(d, "nvidia", "cublas")) for d in dirs) or bool(os.environ.get("CUDA_PATH"))


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


def whisper_files(name: str) -> str:
    """The Whisper model's folder, downloaded first (with download events for
    the app) if it isn't in the Hugging Face cache yet."""
    from faster_whisper.utils import _MODELS, download_model

    try:
        return download_model(name, local_files_only=True)
    except Exception:  # noqa: BLE001  (not downloaded yet)
        pass
    repo = name if "/" in name else _MODELS[name]
    # The files faster_whisper's own download_model fetches.
    files = ["config.json", "preprocessor_config.json", "model.bin", "tokenizer.json", "vocabulary.*"]
    return hub_snapshot(repo, f"Speech model {name}", allow_patterns=files)


def indic_ready(live: bool) -> bool:
    """Can IndicConformer be used for this phrase? Live dictation doesn't wait
    while it loads (~20 s, minutes when downloading; stream.py preloads it):
    Whisper writes those phrases meanwhile. Meetings wait for it."""
    if indic_asr.loaded:
        return True
    if live:
        indic_asr.load_in_background()
        return False
    return indic_asr.load()


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
        self.config: tuple[str, str, str] | None = None  # what was asked: (model, device, need)
        self.choice: tuple[str, str, int, str] | None = None  # what runs: (model, device, GPU, compute type)
        self.active_device = "none"
        self.active_model = "none"
        self.last_used = time.time()
        self._lock = threading.Lock()

    @staticmethod
    def _candidates(model_name: str, device: str, need: str, loaded=None) -> list[tuple[str, str, int, str]]:
        """(model, device, compute_type) to try in order. 'auto' picks by hardware
        and what Whisper has to do (`need`, from `whisper_need`); on CPU, small.

        On an NVIDIA GPU: English only -> large-v3-turbo. Hindi/Gujarati written
        as spoken (IndicConformer writes them; Whisper only writes English and
        tells English from Indian speech) -> medium: on 62 of the user's phrases
        it told them apart as well as large-v3 (2 mistakes each), on ~1.1 GB of
        GPU memory instead of ~2 GB. turbo can't be used there: it called most of
        the user's Gujarati English. Translating -> large-v3, which translates best.

        `loaded`: the choice now in memory; its GPU memory counts as free, since
        it is swapped out for the new one."""
        gpu_auto = {"english": "large-v3-turbo", "detect": "medium"}.get(need, "large-v3")
        dev, index = parse_device(device)
        out = []
        if dev == "cuda" or (dev == "auto" and cuda_usable()):
            free = gpu_free_gb(index)
            if free is not None and loaded and loaded[1] == "cuda" and loaded[2] == index:
                free += GPU_NEED_GB.get(loaded[0], 0.0)
            if model_name != "auto" and (free is None or GPU_NEED_GB.get(model_name, 0) <= free - GPU_SPARE_GB):
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
            # A big model chosen for a GPU would take GBs of RAM and run far too slowly on the CPU.
            fits_cpu = model_name in CPU_MODELS
            out.append((model_name if fits_cpu else cpu_model(), "cpu", 0, "int8"))
        return out

    def load(self, model_name: str = "auto", device: str = "auto", languages: list[str] | None = None, translate=False) -> None:
        need = whisper_need(languages, translate)
        asked = (model_name, device, need)
        with self._lock:
            self.last_used = time.time()
            if self.model is not None and self.config == asked:
                return
            candidates = self._candidates(model_name, device, need, self.choice if self.model is not None else None)
            if self.model is not None and candidates[:1] == [self.choice]:
                # The same model either way (on the CPU `need` changes nothing):
                # loading it again took seconds for nothing.
                self.config = asked
                return
            # Our reference goes first so the GPU doesn't hold two models while
            # the new one loads; a transcription still running keeps the old
            # model until it finishes, then it's freed.
            self._unload()
            from faster_whisper import WhisperModel

            last_err: Exception | None = None
            for choice in candidates:
                name, dev, index, compute = choice
                try:
                    log(f"loading whisper '{name}' on {dev}:{index} ({compute}, {THREADS} threads)")
                    model = WhisperModel(whisper_files(name), device=dev, device_index=index, compute_type=compute,
                                         cpu_threads=THREADS)
                    # CUDA problems (missing cuDNN/cuBLAS) only surface on first use.
                    list(model.transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32))[0])
                    self.model, self.config, self.choice = model, asked, choice
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
            self.config = self.choice = None
            self.active_device = self.active_model = "none"
            gc.collect()

    @property
    def loaded(self) -> bool:
        return self.model is not None

    def _current(self):
        """The loaded model, held by the caller for a whole job: `load` may swap
        `self.model` meanwhile (another job asked for another model). Waits
        while a swap is in progress."""
        with self._lock:
            if self.model is None:
                raise RuntimeError("speech model not loaded")
            return self.model

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
        model = self._current()
        self.last_used = time.time()
        choices = [c for c in languages or [] if c in indic.LANGS and task_for(c, translate) == "transcribe"]
        mixed = self._mixed_language(languages, translate, prefer, choices, live)
        if mixed:
            segs = self._transcribe_mixed(model, audio, mixed, choices, vocabulary, on_progress, vad, cuts)
            return segs if cuts is not None else [untimed(s) for s in segs]
        if languages and len(languages) > 1 and len(audio) > 30 * SAMPLE_RATE:
            segs = self._transcribe_parts(model, audio, vocabulary, on_progress, words, languages, translate, prefer, cuts)
            return segs if cuts is not None else [untimed(s) for s in segs]
        if languages and len(languages) > 1:
            language = self.pick_language(model, audio, languages, prefer, translate, live)
        elif languages:
            language = languages[0]
        task = task_for(language, translate)
        segs = self._transcribe(model, audio, language, vocabulary, on_progress, vad, exact_words(words, language, task), task,
                                live, choices, cuts)
        for seg in segs:
            seg.setdefault("lang", language)
            if words and "words" not in seg:
                seg["words"] = spread_words(seg["text"], seg["start"], seg["end"])
        # "timed" (measured word times) is only for splitting lines by speaker.
        return segs if cuts is not None else [untimed(s) for s in segs]

    @staticmethod
    def pick_language(model, audio: np.ndarray, allowed: list[str], prefer: str | None = None, translate=False,
                      live: bool = False) -> str:
        """Language of this phrase, among the ones the user speaks.

        Whisper tells English from Indian languages reliably, but not Hindi from
        Gujarati: on the user's own Gujarati it answered "Hindi" with ~0.9 and
        Gujarati ~0.0, then effectively translated the speech into Hindi. So it
        only decides English vs Indian language; which Indian language is the
        user's choice (`prefer`) when they speak more than one, unless one is
        written and the other translated (`translate`): then IndicConformer's
        letters decide, as the two go different ways."""
        _, _, probs = model.detect_language(audio)
        p = dict(probs)
        indic_allowed = [code for code in allowed if code != "en"]
        if "en" in allowed:
            p_indic = sum(v for k, v in p.items() if k in INDIC)
            if not indic_allowed or p.get("en", 0.0) >= p_indic:
                return "en"
        if len(indic_allowed) == 1:
            return indic_allowed[0]
        split = len({task_for(code, translate) for code in indic_allowed}) > 1
        if split and all(code in indic.LANGS for code in indic_allowed) and indic_ready(live):
            return indic_asr.pick(audio, prefer if prefer in indic_allowed else indic_allowed[0], indic_allowed)
        if prefer in indic_allowed:
            return prefer
        return max(indic_allowed, key=lambda code: p.get(code, 0.0))

    def _transcribe_parts(self, model, audio, vocabulary, on_progress, words, languages, translate, prefer, cuts=None) -> list[dict]:
        spans = speech_spans(audio, min_silence_ms=700, pad_ms=200)
        out: list[dict] = []
        for i, sp in enumerate(spans):
            part = audio[sp["start"] : sp["end"]]
            offset = sp["start"] / SAMPLE_RATE
            lang = self.pick_language(model, part, languages, prefer, translate)
            choices = [c for c in languages if c in indic.LANGS and task_for(c, translate) == "transcribe"]
            task = task_for(lang, translate)
            part_cuts = [c - offset for c in cuts or [] if 0 < c - offset < len(part) / SAMPLE_RATE]
            for seg in self._transcribe(model, part, lang, vocabulary, None, False, exact_words(words, lang, task), task,
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

    def _transcribe(self, model, audio, language, vocabulary, on_progress, vad, words, task, live=False, choices=None,
                    cuts=None) -> list[dict]:
        self.last_used = time.time()
        if task == "transcribe" and language in indic.LANGS and indic_ready(live):
            # Hindi/Gujarati in their own script; `choices`: the ones to pick between.
            return self._indic_segments(model, audio, language, choices, on_progress, vad, words, cuts, english=None)
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

    def _indic_segments(self, model, audio, language, choices, on_progress, vad, words, cuts, english) -> list[dict]:
        """IndicConformer chunk by chunk, in chunks of up to 12 s cut at pauses
        (see `indic_chunks`) and where the speaker changes (`cuts`).
        `english`: Whisper's English words for
        the whole of `audio` (mixed mode), combined with each chunk (mixed.py);
        a chunk that is mostly English is written as Whisper wrote it."""
        chunks = cut_chunks(indic_chunks(audio, vad), cuts)
        out = []
        for i, (start, end) in enumerate(chunks):
            clip = audio[start:end]
            if on_progress:
                on_progress((i + 1) / len(chunks))
            self.last_used = time.time()
            if vad and not is_real_speech(clip):
                continue
            offset, until = start / SAMPLE_RATE, end / SAMPLE_RATE
            ws, lang = self._indic_words(clip, language, choices)
            ws = [dict(w, s=w["s"] + offset, e=w["e"] + offset, lang="indic") for w in ws]
            if english:
                here = [e for e in english if offset <= (e["s"] + e["e"]) / 2 < until]
                if here:
                    ws = self._combine(model, audio, ws, here, offset, until)
            text = collapse_repeats(join_words(ws))
            if not text:
                continue
            seg = {"start": round(offset, 2), "end": round(until, 2), "text": text, "lang": lang}
            if all(w["lang"] == "en" for w in ws):
                seg["lang"] = "en"
            # Word times come from the decoders (cheap), so they're kept even when
            # exact times weren't asked for: better than spreading them evenly.
            if text == join_words(ws):
                seg["words"] = [{"w": w["w"], "s": round(w["s"], 2), "e": round(w["e"], 2)} for w in ws]
            elif words:  # repeats were collapsed: the words no longer line up
                seg["words"] = spread_words(text, seg["start"], seg["end"])
            out.append(seg)
        self.last_used = time.time()
        return out

    @staticmethod
    def _indic_words(clip: np.ndarray, language, choices) -> tuple[list[dict], str]:
        """IndicConformer's words for a chunk. It sometimes returns nothing (or a
        few words) for a whole 10-12 s chunk, often one heavy with English; cut
        into pieces of up to RETRY_CHUNK_S it wrote them (the user's test meeting:
        an empty 12 s chunk came back as 40 words)."""
        ws, lang = indic_asr.transcribe_words(clip, language, choices)
        seconds = len(clip) / SAMPLE_RATE

        def rnnt(words: list[dict]) -> list[dict]:  # CTC fills RNNT's silences, more roughly
            return [w for w in words if not w.get("ctc")]

        # Also a long stretch without a word: it once wrote only the last 4 s of
        # a 12 s chunk, a normal word count overall.
        if seconds <= RETRY_CHUNK_S or (
            len(rnnt(ws)) >= SPARSE_WORDS_PER_S * seconds and not uncovered(rnnt(ws), 0.0, seconds, RETRY_GAP_S)
        ):
            return ws, lang
        retry: list[dict] = []
        for a, b in indic_chunks(clip, True, RETRY_CHUNK_S):
            part, _ = indic_asr.transcribe_words(clip[a:b], lang)
            retry += [dict(w, s=round(w["s"] + a / SAMPLE_RATE, 2), e=round(w["e"] + a / SAMPLE_RATE, 2)) for w in part]
        log(f"indic: {len(rnnt(ws))} words in {seconds:.0f}s, in smaller pieces {len(rnnt(retry))}")
        return (retry, lang) if len(rnnt(retry)) > len(rnnt(ws)) else (ws, lang)

    def _combine(self, model, audio, ws: list[dict], english: list[dict], start: float, end: float) -> list[dict]:
        """One chunk's IndicConformer words with Whisper's English words for it
        (all times from the start of `audio`).

        Where IndicConformer wrote nothing at all for a while (>= SILENT_INDIC_S)
        though Whisper heard words (its CTC fill included), Whisper is asked which
        language that stretch is, and English is taken as it heard it. Not by
        Whisper's confidence: it was confident in a translation of Gujarati too
        ("I'm half white now, please leave me alone, brother."). Everything else
        is combined by sentence and word (mixed.py), and a chunk that is mostly
        English is written as Whisper wrote it (with its punctuation)."""
        whole = [{"w": e["w"], "s": e["s"], "e": e["e"], "lang": "en"} for e in english]
        direct: list[dict] = []
        for a, b in uncovered(ws, start, end, SILENT_INDIC_S):
            inside = [e for e in english if a <= (e["s"] + e["e"]) / 2 < b]
            stretch = audio[int(a * SAMPLE_RATE) : int(b * SAMPLE_RATE)]
            if len(inside) >= 2 and is_real_speech(stretch) and self._sounds_english(model, stretch):
                direct += inside
        rest = [e for e in english if e not in direct]
        out = merge(ws, rest) if ws and rest else [dict(w, lang=w.get("lang", "indic")) for w in ws]
        for e in direct:
            at = next((x for x, w in enumerate(out) if w["s"] > e["s"]), len(out))
            out.insert(at, {"w": e["w"], "s": e["s"], "e": e["e"], "lang": "en"})
        if out and sum(w["lang"] == "en" for w in out) >= MOSTLY_ENGLISH * len(out):
            return whole
        return out

    @staticmethod
    def _sounds_english(model, clip: np.ndarray) -> bool:
        _, _, probs = model.detect_language(clip)
        p = dict(probs)
        return p.get("en", 0.0) >= sum(v for k, v in p.items() if k in INDIC)

    @staticmethod
    def _mixed_language(languages, translate, prefer, choices, live: bool = False) -> str | None:
        """English plus Hindi/Gujarati written in their own script, nothing
        translated: the Indian language to write (else None, the usual way)."""
        others = [c for c in languages or [] if c != "en"]
        if "en" not in (languages or []) or not choices or len(choices) != len(others):
            return None
        if not indic_ready(live):
            return None
        return prefer if prefer in choices else choices[0]

    def _transcribe_mixed(self, model, audio, language, choices, vocabulary, on_progress, vad, cuts) -> list[dict]:
        """English and Hindi/Gujarati, also within one sentence.

        No language detection: IndicConformer writes every chunk, and Whisper
        reads the same audio as English once (in 30 s windows, not per chunk:
        on the CPU each Whisper call costs ~3-5 s however short the audio). The
        two are combined word by word (mixed.py): Gujarati stays Gujarati, English
        is written in English, and English-only chunks come out as Whisper wrote
        them. Measured on the CPU the separate detection plus a second Whisper
        call per chunk took 124 s for 108 s of audio.

        Progress: the Whisper pass counts as the first half, IndicConformer as
        the second (a rough split; a meeting used to sit at 0% through the
        whole Whisper pass)."""
        self.last_used = time.time()
        segments, info = model.transcribe(
            audio, language="en", task="transcribe", beam_size=5, vad_filter=vad,
            vad_parameters={"min_silence_duration_ms": 500},
            initial_prompt=(vocabulary.strip().rstrip(".") + ".") if vocabulary and vocabulary.strip() else None,
            # One try: on Gujarati speech Whisper is unsure all the time, and the
            # retries at higher temperatures only slowed it down (GPU 27 s -> 44 s).
            condition_on_previous_text=False, word_timestamps=True, temperature=(0.0,),
        )
        english = []
        for s in segments:  # decoded as they're read
            self.last_used = time.time()
            if on_progress and info.duration:
                on_progress(min(1.0, s.end / info.duration) / 2)
            # Whisper's loops and inventions on noise (as in `_transcribe`), and
            # its vocabulary hint repeated over near-silence ("Nishchay, Voice Desk.").
            if s.compression_ratio > 2.4 or (s.no_speech_prob > 0.7 and s.avg_logprob < -1.0):
                continue
            if echoes_vocabulary(s.text, vocabulary):
                continue
            english += [
                {"w": w.word.strip(), "s": round(w.start, 2), "e": round(w.end, 2), "p": float(w.probability)}
                for w in (s.words or []) if w.word.strip()
            ]
        second_half = (lambda f: on_progress(0.5 + f / 2)) if on_progress else None
        return self._indic_segments(model, audio, language, choices, second_half, vad, True, cuts, english)


# Fewer IndicConformer words per second than this in a chunk: try again in
# smaller pieces (speech is ~2-4 words/s).
SPARSE_WORDS_PER_S = 0.8
RETRY_CHUNK_S = 6
RETRY_GAP_S = 3.0
# Share of a chunk's words that are English for it to be written as
# Whisper's English (with its punctuation) instead of word by word.
MOSTLY_ENGLISH = 0.7


# IndicConformer silent this long where Whisper heard words: check the language there.
SILENT_INDIC_S = 2.0


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


def indic_chunks(audio: np.ndarray, vad: bool = True, max_s: float = indic.MAX_CHUNK_S) -> list[tuple[int, int]]:
    """Cut audio into pieces IndicConformer decodes reliably (<= `max_s`).

    Stretches of speech are joined while they fit; a longer stretch is cut at
    its shorter pauses (breaths), and only as a last resort mid-speech. Tested:
    decoding each short stretch alone lost words, and long inputs lost the start.
    Without `vad` (live dictation) silence is kept, but long phrases still split."""
    limit = int(max_s * SAMPLE_RATE)

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
