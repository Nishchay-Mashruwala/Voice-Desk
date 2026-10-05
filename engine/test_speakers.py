"""Tests for telling speakers apart in meeting transcripts (no models needed).

  .venv/Scripts/python engine/test_speakers.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from meeting import is_echo_text, speaker_changes, speaker_pieces, split_by_speaker, transcribe_with_speakers  # noqa: E402
import numpy as np  # noqa: E402

from speakers import fold_tiny, match_people  # noqa: E402
from transcriber import cut_chunks, indic_chunks  # noqa: E402


def words(*spec):
    """("hi", 0.0, 0.4), ... -> [{"w": "hi", "s": 0.0, "e": 0.4}, ...]"""
    return [{"w": w, "s": s, "e": e} for w, s, e in spec]


def test_tiny_speaker_joins_neighbour():
    turns = [(0.0, 5.0, "A"), (5.1, 5.6, "C"), (6.0, 9.0, "B")]
    assert fold_tiny(turns) == [(0.0, 5.0, "A"), (5.1, 5.6, "A"), (6.0, 9.0, "B")]


def test_real_speakers_kept():
    turns = [(0.0, 2.0, "A"), (2.0, 4.0, "B")]
    assert fold_tiny(turns) == turns


def test_pieces_drop_blips_and_join_same_person():
    turns = [(0.0, 2.0, "A"), (2.0, 2.04, "B"), (2.5, 4.0, "A"), (4.2, 6.0, "B")]
    assert speaker_pieces(turns) == [(0.0, 4.0, "A"), (4.2, 6.0, "B")]
    assert speaker_changes(speaker_pieces(turns)) == [4.1]


def test_whisper_line_split_at_speaker_change():
    pieces = [(0.0, 1.0, "A"), (1.2, 3.0, "B")]
    seg = {"start": 0.0, "end": 2.6, "text": "are you there yes I am", "timed": True,
           "words": words(("are", 0.0, 0.3), ("you", 0.3, 0.5), ("there", 0.5, 0.9),
                          ("yes", 1.3, 1.6), ("I", 1.7, 1.8), ("am", 1.8, 2.6))}
    out = split_by_speaker([seg], pieces)
    assert [(s["speaker"], s["text"]) for s in out] == [("A", "are you there"), ("B", "yes I am")]
    assert out[1]["start"] == 1.3 and all("timed" not in s for s in out)


def test_one_stray_word_stays_with_its_neighbours():
    pieces = [(0.0, 1.0, "A"), (1.0, 1.2, "B"), (1.2, 3.0, "A")]
    seg = {"start": 0.0, "end": 2.0, "text": "one two three", "timed": True,
           "words": words(("one", 0.2, 0.8), ("two", 1.05, 1.15), ("three", 1.5, 2.0))}
    assert [s["speaker"] for s in split_by_speaker([seg], pieces)] == ["A"]


def test_estimated_line_takes_main_speaker():
    pieces = [(0.0, 1.0, "A"), (1.0, 5.0, "B")]
    seg = {"start": 0.5, "end": 5.0, "text": "ઓહ અમેરિકન એટલે", "words": words(("ઓહ", 0.5, 2.0), ("અમેરિકન", 2.0, 4.0))}
    out = split_by_speaker([seg], pieces)
    assert len(out) == 1 and out[0]["speaker"] == "B"


def test_indic_chunks_cut_at_speaker_changes():
    sr = 16000
    assert cut_chunks([(0, 10 * sr)], [2.0, 2.1, 9.9]) == [(0, 2 * sr), (2 * sr, 10 * sr)]
    assert cut_chunks([(0, 10 * sr)], None) == [(0, 10 * sr)]


def test_chunks_cut_at_changes_keep_their_offsets():
    sr = 16000
    chunks = [(0, 12 * sr), (15 * sr, 20 * sr)]
    # A change inside each chunk; one 0.1 s from an edge is too close to cut.
    assert cut_chunks(chunks, [5.0, 17.5, 19.95]) == [(0, 5 * sr), (5 * sr, 12 * sr), (15 * sr, int(17.5 * sr)),
                                                     (int(17.5 * sr), 20 * sr)]
    assert cut_chunks(chunks, [13.0]) == chunks  # between chunks


def test_long_audio_is_cut_into_model_sized_chunks():
    sr = 16000
    silence = np.zeros(30 * sr, np.float32)
    # Live dictation (no VAD) keeps everything, split at the 12 s the model reads well.
    assert indic_chunks(silence, vad=False) == [(0, 12 * sr), (12 * sr, 24 * sr), (24 * sr, 30 * sr)]
    assert indic_chunks(silence[: 5 * sr], vad=False) == [(0, 5 * sr)]
    assert indic_chunks(silence, vad=True) == []  # nothing said


def test_speech_with_only_blips_of_speakers_is_still_transcribed():
    calls = []

    def tx(audio, on_progress=None, cuts=None):
        calls.append(cuts)
        return [{"start": 0.0, "end": 1.0, "text": "No."}]

    blips = [(0.0, 0.1, "SPEAKER_00"), (0.5, 0.6, "SPEAKER_01")]
    out = transcribe_with_speakers(np.zeros(16000, np.float32), blips, tx, unknown="Others")
    assert out == [{"start": 0.0, "end": 1.0, "text": "No.", "speaker": "Others"}] and calls == [None]


def test_echo_of_the_call_is_detected():
    others = [{"start": 10.0, "end": 13.0, "text": "Can you send the report by Friday?"}]
    echo = {"start": 10.3, "end": 13.4, "text": "can you send the report by friday"}
    assert is_echo_text(echo, others)


def test_own_words_are_not_echo():
    others = [{"start": 10.0, "end": 13.0, "text": "Can you send the report by Friday?"}]
    reply = {"start": 13.6, "end": 15.0, "text": "Sure, I will send it tomorrow."}
    assert not is_echo_text(reply, others)
    # Same words, but long after: the user repeating something, not an echo.
    later = {"start": 30.0, "end": 33.0, "text": "can you send the report by friday"}
    assert not is_echo_text(later, others)


def test_remembered_voices_name_the_closest_speaker_only():
    voices = {"SPEAKER_00": np.array([1.0, 0.0]), "SPEAKER_01": np.array([0.0, 1.0]), "SPEAKER_02": np.array([0.6, 0.8])}
    people = [{"name": "Priya", "embedding": [0.9, 0.1]}, {"name": "Raj", "embedding": [-1.0, 0.0]}]
    # Priya matches SPEAKER_00 best; she can't also name SPEAKER_02; Raj matches nobody.
    assert match_people(voices, people) == {"SPEAKER_00": "Priya"}
    assert match_people(voices, []) == {}


if __name__ == "__main__":
    tests = [v for k, v in dict(globals()).items() if k.startswith("test_")]
    for t in tests:
        t()
    print(f"all {len(tests)} passed")
