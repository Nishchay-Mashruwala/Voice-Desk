"""Finding speech in audio (Silero VAD) and cleaning up recognised text."""

from __future__ import annotations

import numpy as np

from runtime import SAMPLE_RATE
import commands

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
