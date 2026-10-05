"""Tests for English inside Gujarati speech (mixed.py; no models needed).
Word times and Whisper's words are taken from the user's "Gujarati Test" meeting.

  .venv/Scripts/python engine/test_mixed.py
"""

from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from indic import _words, uncovered  # noqa: E402
from mixed import english_sounds, indic_sounds, is_english, join_words, merge, sound_similarity  # noqa: E402


def g(*spec):
    """IndicConformer words: ("તમે", 0.0, 0.2), ..."""
    return [{"w": w, "s": s, "e": e} for w, s, e in spec]


def en(*spec):
    """Whisper's forced-English words: ("Are", 0.26, 0.0, 0.2), ... (word, probability, start, end)"""
    return [{"w": w, "p": p, "s": s, "e": e} for w, p, s, e in spec]


def alike(gu: str, english: str) -> float:
    return sound_similarity("".join(indic_sounds(x) for x in gu.split()), "".join(english_sounds(x) for x in english.split()))


def test_english_spelled_in_gujarati_sounds_like_the_english():
    for gu, english in [("બેકગ્રાઉન્ડ", "background"), ("અફકોર્સ", "of course"), ("એક્ચુલી", "actually"),
                        ("સ્કોટિશ", "Scottish"), ("ફ્રેકલ્સ", "freckles"), ("સ્ટેજ", "stage"), ("નોર્મલી", "normally")]:
        assert alike(gu, english) >= 0.8, (gu, english, alike(gu, english))


def test_gujarati_and_its_translation_dont():
    for gu, english in [("ભૂખ", "hungry"), ("પાણી", "water"), ("કારણ", "because"), ("ગુસ્સા", "anger"), ("સરસ", "nice")]:
        assert alike(gu, english) < 0.5, (gu, english, alike(gu, english))


def test_english_words_with_endings():
    assert all(is_english(w) for w in ["actually", "freckles", "normally", "stopped", "Scottish", "background"])
    # Whisper writing Gujarati in Latin letters isn't English.
    assert not any(is_english(w) for w in ["aavde", "hoon", "khaali", "gusa", "varso"])


def test_english_word_replaces_its_gujarati_spelling():
    words = g(("હા", 4.48, 4.64), ("એનું", 4.72, 4.88), ("બેકગ્રાઉન્ડ", 4.96, 5.6), ("તો", 5.68, 5.76), ("સ્કોટિશ", 5.84, 6.3), ("છે", 6.4, 6.5))
    english = en(("Yes,", 0.67, 4.9, 5.1), ("her", 0.32, 5.26, 5.28), ("background", 0.99, 5.28, 5.6),
                 ("is", 0.98, 5.64, 5.8), ("Scottish.", 0.97, 5.8, 6.3))
    assert join_words(merge(words, english)) == "હા એનું background તો Scottish છે"


def test_translation_and_latin_gujarati_are_not_used():
    words = g(("ભૂખ", 0.0, 0.3), ("લાગી", 0.4, 0.7), ("છે", 0.8, 0.9), ("આવડે", 1.0, 1.3), ("છે", 1.4, 1.5))
    english = en(("You", 0.05, 0.0, 0.1), ("feel", 0.42, 0.1, 0.3), ("hungry,", 0.98, 0.3, 0.8),
                 ("aavde", 0.97, 1.0, 1.3), ("she", 0.9, 1.4, 1.5))
    assert join_words(merge(words, english)) == "ભૂખ લાગી છે આવડે છે"


def test_indian_names_stay_gujarati_alone():
    # Whisper translated "તમે ગુજરાતી છો" as "Are you from Gujarat?"
    words = g(("તમે", 0.0, 0.24), ("ગુજરાતી", 0.24, 0.64), ("છો", 0.64, 0.8))
    english = en(("Are", 0.26, 0.0, 0.22), ("you", 0.99, 0.22, 0.3), ("from", 0.33, 0.3, 0.3), ("Gujarat?", 0.97, 0.3, 0.9),
                 ("Yeah,", 0.44, 1.08, 1.3))
    assert join_words(merge(words, english)) == "તમે ગુજરાતી છો"


def test_gujarati_ending_stays_on_the_english_word():
    words = g(("તો", 7.2, 7.3), ("કેન્ઝી", 7.36, 7.8), ("સિટીથી", 7.92, 8.3), ("છે", 8.4, 8.5))
    english = en(("from", 0.99, 7.42, 7.5), ("Kansas", 0.74, 7.5, 7.78), ("City.", 0.77, 7.78, 8.2))
    assert join_words(merge(words, english)) == "તો Kansas Cityથી છે"


def test_gujarati_leftovers_inside_an_english_phrase_become_whispers_words():
    words = g(("જેમાં", 1.5, 1.8), ("કેન", 2.3, 2.5), ("બી", 2.6, 2.7), ("ધૂ", 2.8, 3.0), ("યુ", 3.7, 3.8), ("લાઈક", 3.84, 4.0),
              ("ટુ", 4.0, 4.1), ("ડુ", 4.1, 4.18), ("અ", 4.18, 4.2), ("ફિલ્મ", 4.56, 4.9))
    english = en(("can", 0.86, 2.38, 2.6), ("be", 0.97, 2.6, 2.78), ("the...", 0.71, 2.78, 3.5), ("Would", 0.77, 3.56, 3.74),
                 ("you", 0.99, 3.74, 3.84), ("like", 0.99, 3.84, 4.0), ("to", 1.0, 4.0, 4.1), ("do", 0.98, 4.1, 4.18),
                 ("a", 0.98, 4.18, 4.28), ("film?", 0.97, 4.56, 4.9))
    # Taken as two sentences, with Whisper's punctuation.
    assert join_words(merge(words, english)) == "જેમાં can be the... Would you like to do a film?"


def test_everyday_gujarati_between_english_words_stays():
    # "Gujarati. [એટલે મારા] dad": Whisper's words between are a translation ("So my").
    words = g(("હેવ", 2.96, 3.2), ("ગુજરાતી", 3.28, 3.68), ("એટલે", 4.0, 4.3), ("મારા", 4.32, 4.5), ("ડેડ", 4.56, 4.8))
    english = en(("have", 0.68, 2.9, 3.2), ("Gujarati.", 0.83, 3.3, 3.7), ("So", 0.49, 3.9, 4.2), ("my", 0.71, 4.3, 4.5),
                 ("dad", 0.67, 4.56, 4.8))
    assert "એટલે મારા" in join_words(merge(words, english))


def test_english_the_gujarati_model_dropped_is_put_back():
    words = g(("તો", 0.0, 0.2), ("આવી", 0.3, 0.6), ("ગુજરાતી", 1.0, 1.5))
    english = en(("Wow,", 0.93, 6.48, 6.8), ("that's", 0.99, 6.88, 7.1), ("amazing.", 0.99, 7.1, 7.5),
                 ("Yeah,", 0.91, 7.56, 7.8), ("we", 1.0, 7.8, 7.94))
    assert join_words(merge(words, english)) == "તો આવી ગુજરાતી Wow, that's amazing. Yeah, we"


def test_short_confident_translation_in_a_small_gap_is_not():
    # "ભરોસો નહીં" -> "don't believe in": confident, but a translation.
    words = g(("તમારા", 0.0, 0.4), ("પર", 0.5, 0.6), ("ભરો", 0.7, 0.9), ("વાળા", 2.2, 2.5))
    english = en(("don't", 0.97, 1.1, 1.3), ("believe", 0.98, 1.3, 1.6), ("in", 0.93, 1.6, 1.8))
    assert join_words(merge(words, english)) == "તમારા પર ભરો વાળા"


def spread(text: str, start: float, step: float = 0.3):
    """Gujarati words at even times."""
    return [{"w": w, "s": round(start + k * step, 2), "e": round(start + k * step + step * 0.8, 2)} for k, w in enumerate(text.split())]


def heard(text: str, start: float, p: float = 0.9, step: float = 0.3):
    """Whisper's words at even times, all with probability p."""
    return [{"w": w, "p": p, "s": round(start + k * step, 2), "e": round(start + k * step + step * 0.8, 2)} for k, w in enumerate(text.split())]


def test_english_sentence_spelled_in_gujarati_becomes_the_english_sentence():
    # Word by word this came out "કેન બી ધ વુડ you like ટુ ડુ અ ગુજરાતી film".
    words = spread("તો આવી એક લવ સ્ટોરી થઈ શકે કે જેમાં", 0.0) + spread("વુડ યુ લાઈક ટુ ડુ અ ગુજરાતી ફિલ્મ", 3.0)
    english = heard("Would you like to do a Gujarati film?", 3.0, p=0.86)
    assert join_words(merge(words, english)) == "તો આવી એક લવ સ્ટોરી થઈ શકે કે જેમાં Would you like to do a Gujarati film?"


def test_translation_of_a_gujarati_sentence_is_not_taken():
    # Whisper's translations, confident and sharing loanwords ("producer", "Gujarati").
    for gu, en in [
        ("આગળ ભાઈ કોને પ્રોડ્યુસર બનવું છે ગુજરાતી પિક્ચર માં", "ever become a producer in a Gujarati film?"),
        ("અરે મને તો કરું હેફ વા ટુ છોડી દે ને ભાઈ", "I'm half white now, please leave me alone, brother."),
        ("કે મમ્મી મને ગુસ્સા", "my mom made me angry, she says, I"),
        # Loanwords make these sound alike; છે, તો, મારા show it's Gujarati.
        ("એટલે મારા ડેડ તો ગુજરાતી છે બોમ્બે", "So my dad is Gujarati, Bombay."),
    ]:
        merged = merge(spread(gu, 0.0), heard(en, 0.0, p=0.75))
        assert sum(w["lang"] == "en" for w in merged) <= 1, (gu, join_words(merged))


def test_stretches_without_words():
    ws = g(("તો", 1.0, 1.2), ("આવી", 1.3, 1.6), ("એક", 4.5, 4.7))
    assert uncovered(ws, 0.0, 8.0, 2.0) == [(1.6, 4.5), (4.7, 8.0)]
    assert uncovered([], 2.0, 5.0, 2.0) == [(2.0, 5.0)]
    assert uncovered(ws, 0.5, 5.0, 3.0) == []


def test_decoder_pieces_become_timed_words():
    # "▁" starts a word; a lone "▁" doesn't make an empty one.
    pieces = [("▁ગુ", 3), ("જ", 4), ("રાતી", 5), ("▁", 8), ("▁છો", 9), ("▁", 12), ("ને", 13)]
    assert _words(pieces, 10.0, 0.08) == [
        {"w": "ગુજરાતી", "s": 10.24, "e": 10.48},
        {"w": "છો", "s": 10.72, "e": 10.8},
        {"w": "ને", "s": 11.04, "e": 11.12},
    ]


def test_all_gujarati_when_whisper_heard_no_english():
    words = g(("ભૂખ", 0.0, 0.3), ("લાગી", 0.4, 0.7))
    assert [w["lang"] for w in merge(words, [])] == ["indic", "indic"]


def test_whisper_task_per_language():
    from transcriber import task_for

    assert task_for("gu", ["gu"]) == "translate"
    assert task_for("hi", ["gu"]) == "transcribe"
    assert task_for("hi", True) == "translate"
    assert task_for("en", True) == "transcribe"
    assert task_for("gu", False) == "transcribe"
    assert task_for(None, True) == "transcribe"


def test_what_whisper_must_do():
    from indic import indic_asr
    from transcriber import whisper_need

    saved = indic_asr.failed
    try:
        indic_asr.failed = None
        assert whisper_need(None, False) == "english"
        assert whisper_need(["en"], True) == "english"
        assert whisper_need(["en", "gu"], False) == "detect"  # IndicConformer writes Gujarati
        assert whisper_need(["en", "gu"], ["gu"]) == "indic"  # Whisper translates it
        assert whisper_need(["en", "hi", "gu"], ["gu"]) == "indic"
        indic_asr.failed = "no token"  # just failed: Whisper writes Gujarati itself
        indic_asr.failed_at = time.time()
        assert whisper_need(["en", "gu"], False) == "indic"
        indic_asr.failed_at = time.time() - indic_asr.RETRY_AFTER_S  # long enough ago to try again
        assert whisper_need(["en", "gu"], False) == "detect"
    finally:
        indic_asr.failed = saved


class _Loaded:
    """Stands in for IndicConformer: loaded, picks `answer`."""

    def __init__(self, answer: str) -> None:
        self.answer = answer

    def __enter__(self):
        from indic import indic_asr

        self.saved = indic_asr.model
        indic_asr.model = object()
        indic_asr.pick = lambda audio, prefer, choices: self.answer
        return self

    def __exit__(self, *exc) -> None:
        from indic import indic_asr

        indic_asr.model = self.saved
        del indic_asr.pick  # back to the class's method


def test_mixed_english_and_gujarati_mode():
    from transcriber import Transcriber

    mixed = Transcriber._mixed_language
    with _Loaded("gu"):
        assert mixed(["en", "gu"], False, None, ["gu"]) == "gu"
        assert mixed(["en", "hi", "gu"], False, "gu", ["hi", "gu"]) == "gu"
        assert mixed(["en", "hi", "gu"], False, None, ["hi", "gu"]) == "hi"
        assert mixed(["en", "hi", "gu"], ["gu"], "gu", ["hi"]) is None  # Gujarati is translated
        assert mixed(["gu"], False, None, ["gu"]) is None  # no English
    from indic import indic_asr

    if not indic_asr.loaded:  # live dictation doesn't wait for it to load
        indic_asr.load_in_background = lambda hf_token=None: None
        try:
            assert mixed(["en", "gu"], False, None, ["gu"], live=True) is None
        finally:
            del indic_asr.load_in_background


class _Whisper:
    """Stands in for Whisper's language detection."""

    def __init__(self, **probs: float) -> None:
        self.probs = list(probs.items())

    def detect_language(self, audio):
        return None, None, self.probs


def test_hindi_or_gujarati_when_only_one_is_translated():
    import numpy as np

    from transcriber import Transcriber

    pick, audio = Transcriber.pick_language, np.zeros(16000, np.float32)
    langs = ["en", "hi", "gu"]
    # Whisper calls Gujarati "Hindi"; only one of them is translated, so
    # IndicConformer's letters decide which one this is.
    with _Loaded("hi"):
        assert pick(_Whisper(hi=0.9, en=0.05), audio, langs, "gu", ["gu"]) == "hi"
        assert pick(_Whisper(hi=0.1, en=0.8), audio, langs, "gu", ["gu"]) == "en"
        # Both written (or both translated): the user's choice, as before.
        assert pick(_Whisper(hi=0.9, en=0.05), audio, langs, "gu", False) == "gu"
        assert pick(_Whisper(hi=0.9, en=0.05), audio, langs, "gu", True) == "gu"


if __name__ == "__main__":
    tests = [v for k, v in dict(globals()).items() if k.startswith("test_")]
    for t in tests:
        t()
    print(f"all {len(tests)} passed")
