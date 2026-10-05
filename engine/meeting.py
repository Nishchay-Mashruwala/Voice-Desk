"""Meetings: who spoke when, transcription by speaker, and naming speakers."""

from __future__ import annotations

import os
import threading

import numpy as np

import speakers
from indic import indic_asr
from recordings import read_audio
from runtime import SAMPLE_RATE, log, send
from speakers import diarize, name_speakers, speaker_audio, voice_of
from speech import speech_seconds
from stream import streams
from transcriber import preload_indic, transcriber
from voice import VOICE_THRESHOLD, load_profile, voice_score

# --------------------------------------------------------------------------- #
# Meetings
# --------------------------------------------------------------------------- #


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


def transcribe_with_speakers(audio: np.ndarray, turns, tx, on_progress=None, unknown: str = "Speaker") -> list[dict]:
    """Transcribe the whole recording once (Whisper needs the context), cutting
    Hindi/Gujarati chunks where the speaker changes, then split lines by speaker.

    When every turn is a blip (< MIN_TURN_S) there was still speech: it is
    transcribed without speakers and labelled `unknown`, as when speaker
    detection finds nothing (it used to come back empty)."""
    pieces = speaker_pieces(turns)
    if not pieces:
        segs = tx(audio, on_progress)
        for s in segs:
            s["speaker"] = unknown
        return segs
    segs = tx(audio, on_progress, cuts=speaker_changes(pieces))
    return split_by_speaker(segs, pieces)

# Echo: the speakers' sound reaches the mic up to this much later (room + device delays).
ECHO_DELAY_S = 0.5
# Share of a mic line's words also heard on the computer audio that makes it an echo.
ECHO_SHARE = 0.6


def _tokens(text: str) -> list[str]:
    return [t for t in (w.strip(".,!?;:\"'()").lower() for w in text.split()) if t]


def is_echo_text(line: dict, others: list[dict]) -> bool:
    """Is this mic line the other people's words, picked up from the speakers?

    True when most of its words were also said on the computer audio at the same
    moment (allowing for the speakers-to-mic delay)."""
    words = _tokens(line["text"])
    if not words:
        return False
    heard: set[str] = set()
    for o in others:
        if o["start"] - ECHO_DELAY_S <= line["end"] and o["end"] + ECHO_DELAY_S >= line["start"]:
            heard.update(_tokens(o["text"]))
    shared = sum(1 for w in words if w in heard)
    return shared / len(words) >= ECHO_SHARE and (len(words) >= 2 or shared == 1 and bool(heard))


def drop_echo(me: list[dict], others: list[dict], mic: np.ndarray, system: np.ndarray, profile) -> list[dict]:
    """Without headphones the mic also hears the call. Keep only mic lines that
    are the user: drop lines repeating the computer audio's words, and (with a
    voice profile) lines in someone else's voice said while others were talking."""
    from speech import speech_spans

    talking = [(s["start"] / SAMPLE_RATE, s["end"] / SAMPLE_RATE) for s in speech_spans(system)] if len(system) else []
    kept = []
    for line in me:
        if is_echo_text(line, others):
            log(f"echo (same words as the call): {line['text'][:60]!r}")
            continue
        if profile is not None and len(mic):
            during_call = any(a - ECHO_DELAY_S <= line["end"] and b + ECHO_DELAY_S >= line["start"] for a, b in talking)
            clip = mic[int(line["start"] * SAMPLE_RATE) : int(line["end"] * SAMPLE_RATE)]
            score = voice_score(profile, clip) if during_call else None
            if score is not None and score < VOICE_THRESHOLD:
                log(f"echo (not your voice, {score:.2f}): {line['text'][:60]!r}")
                continue
        kept.append(line)
    return kept


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
    """SPEAKER_00 -> Speaker 1, in order of first appearance. 'Me', 'Others' and
    remembered names are kept."""
    mapping: dict[str, str] = {}
    for seg in segments:
        spk = seg["speaker"]
        if not spk.startswith("SPEAKER_"):  # "Me", "Others", or a remembered name
            continue
        if spk not in mapping:
            mapping[spk] = f"Speaker {len(mapping) + 1}"
        seg["speaker"] = mapping[spk]


def cmd_speaker_voice(req: dict) -> dict:
    """{"path": recording, "spans": [[start_s, end_s], ...]} -> that speaker's voice, to remember."""
    audio = read_audio(req["path"])
    clip = speaker_audio(audio, req["spans"])
    if len(clip) < 2 * SAMPLE_RATE:
        raise ValueError("Not enough of their speech to remember the voice (needs 2 s or more)")
    return {"embedding": [round(float(x), 5) for x in voice_of(clip)]}


# Meetings being processed now (see `free_meeting_models`).
_running = 0
_running_lock = threading.Lock()


def cmd_meeting(req: dict) -> dict:
    global _running
    with _running_lock:
        _running += 1
    try:
        return _meeting(req)
    finally:
        with _running_lock:
            _running -= 1
            last = _running == 0
        if last:
            free_meeting_models()


def free_meeting_models() -> None:
    """After a meeting, free IndicConformer (~1 GB) and the speaker models
    (~0.1 GB) for the task AI that reads the transcript next (llama-server,
    ~3 GB), which matters on 8 GB computers. Whisper stays for dictation, and
    nothing is freed while a dictation may need IndicConformer."""
    if streams:
        return
    indic_asr.unload()
    speakers.unload()
    log("meeting done: freed the Hindi/Gujarati and speaker models")


def _meeting(req: dict) -> dict:
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
    people = req.get("people") or []  # remembered voices: [{"name", "embedding"}]


    mic = read_audio(req["mic_path"]) if req.get("mic_path") and os.path.exists(req["mic_path"]) else np.zeros(0, np.float32)
    system = read_audio(req["system_path"]) if req.get("system_path") and os.path.exists(req["system_path"]) else np.zeros(0, np.float32)
    mic_segments = req.get("mic_segments")
    progress("Checking audio", 2)
    has_system = speech_seconds(system) >= 2.0
    has_mic = mic_segments is not None or speech_seconds(mic) >= 0.5
    log(f"meeting: mic {len(mic) / SAMPLE_RATE:.0f}s (speech={has_mic}), "
        f"system {len(system) / SAMPLE_RATE:.0f}s (speech={has_system})")

    segments: list[dict] = []
    me: list[dict] = []  # the user's mic in a call; checked for echo once the call is transcribed
    if mic_segments is not None:
        me = [
            {"start": s["start"], "end": s["end"], "text": s["text"], "speaker": "Me", "words": s.get("words")}
            for s in mic_segments
        ]
    elif has_mic:
        if has_system:
            progress("Transcribing your microphone", 5)
            me = tx(mic, lambda f: progress("Transcribing your microphone", 5 + f * 35))
            for s in me:
                s["speaker"] = "Me"
        else:
            # In-person meeting: everyone is on the mic. Find who speaks when,
            # transcribe each turn, then find the user by voice.
            progress("Identifying speakers", 5)
            try:
                turns = name_speakers(mic, diarize(mic), people)
            except Exception as e:  # noqa: BLE001
                warn(f"Speaker detection skipped: {e}")
                turns = []
            if turns:
                progress("Transcribing", 40)
                mic_segs = transcribe_with_speakers(mic, turns, tx, lambda f: progress("Transcribing", 40 + f * 55), "Speaker")
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
            turns = name_speakers(system, diarize(system), people)
        except Exception as e:  # noqa: BLE001
            warn(f"Speaker detection skipped: {e}")
            turns = []
        if turns:
            progress("Transcribing meeting audio", 65)
            sys_segs = transcribe_with_speakers(system, turns, tx, lambda f: progress("Transcribing meeting audio", 65 + f * 33),
                                                "Others")
        else:
            progress("Transcribing meeting audio", 65)
            sys_segs = tx(system, lambda f: progress("Transcribing meeting audio", 65 + f * 33))
            for s in sys_segs:
                s["speaker"] = "Others"
        segments += sys_segs
        me = drop_echo(me, sys_segs, mic, system, profile)
    segments += me

    segments.sort(key=lambda s: s["start"])
    friendly_speaker_names(segments)
    progress("Transcript ready", 100)
    duration = max(len(mic), len(system)) / SAMPLE_RATE
    if mic_segments:
        duration = max(duration, max(s["end"] for s in mic_segments))
    return {"segments": segments, "duration": round(duration, 1), "others_spoke": has_system}
