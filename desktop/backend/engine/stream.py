"""Live dictation: mic audio in, finished phrases (and voice commands) out."""

from __future__ import annotations

import base64
import threading
import traceback

import numpy as np

from runtime import SAMPLE_RATE, log, send
from speech import echoes_vocabulary, is_real_speech, speech_spans
from transcriber import HALLUCINATIONS, preload_indic, transcriber
from voice import load_profile, voice_score
import commands

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
        except Exception as e:  # noqa: BLE001  (only a failure to start ends dictation)
            log(traceback.format_exc())
            send({"event": "stream_error", "sid": self.sid, "message": str(e)})
            self.done.set()
            return
        try:
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
                    try:
                        self.step(final)
                    except Exception:  # noqa: BLE001
                        # Drop what's buffered, or the same audio fails again every step.
                        log(f"skipped {len(self.buf) / SAMPLE_RATE:.1f}s of audio: {traceback.format_exc()}")
                        self._consume(len(self.buf))
                if final:
                    break
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
        """Send one finished phrase. A phrase that fails to transcribe is
        skipped; dictation goes on with the next one."""
        try:
            self._emit(audio, abs_start)
        except Exception:  # noqa: BLE001
            log(f"skipped a {len(audio) / SAMPLE_RATE:.1f}s phrase: {traceback.format_exc()}")

    def _emit(self, audio: np.ndarray, abs_start: int) -> None:
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
        # Retries keep the language settings: without them a mixed English +
        # Gujarati phrase was read again as Gujarati only, or not translated.
        same = {"languages": langs, "translate": translate, "prefer": prefer}
        if echoes_vocabulary(text, vocab):
            # Decode again without the hint; keep it only if real words remain.
            segs = transcriber.transcribe(audio, lang or o.get("language"), None, vad=False, words="auto", live=True, **same)
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
            retry = transcriber.transcribe(audio, lang or o.get("language"), None, vad=False, words=True, live=True, **same)
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
