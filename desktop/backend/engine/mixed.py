"""English inside Hindi/Gujarati speech, written in English.

IndicConformer writes everything in the Indian script, so English said in the
middle of Gujarati comes out spelled by sound ("અફકોર્સ" for "of course"), and
whole English sentences come out garbled or are dropped. Whisper, forced to
English on the same audio, writes those English parts right, but it translates
the Gujarati parts (and sometimes writes them in Latin letters, "aavde hoon se").

So the two are combined by time and by sound:
- A Gujarati word is replaced by the English Whisper heard at the same moment
  when they sound alike and Whisper's words are real English words (a Gujarati
  word and Whisper's translation of it don't sound alike: "ભૂખ" / "hungry").
- English that IndicConformer dropped (no Gujarati words at that time) is put
  back when Whisper was confident about a run of real English words.

Measured on the user's "Gujarati Test" meeting (a Gujarati conversation with
English in between).
"""

from __future__ import annotations

import os
import re
import sys
from functools import lru_cache

# --------------------------------------------------------------------------- #
# Sounds
# --------------------------------------------------------------------------- #

# Gujarati's block mirrors Devanagari's layout (both from ISCII): same offsets.
GUJARATI_TO_DEVANAGARI = 0x0A80 - 0x0900

# Devanagari letters -> rough sound classes (aspirated = plain, retroflex = dental).
CONSONANTS = {
    "क": "k", "ख": "k", "ग": "g", "घ": "g", "ङ": "n", "च": "c", "छ": "c", "ज": "j", "झ": "j", "ञ": "n",
    "ट": "t", "ठ": "t", "ड": "d", "ढ": "d", "ण": "n", "त": "t", "थ": "t", "द": "d", "ध": "d", "न": "n",
    "प": "p", "फ": "p", "ब": "b", "भ": "b", "म": "m", "य": "y", "र": "r", "ल": "l", "ळ": "l", "व": "v",
    "श": "s", "ष": "s", "स": "s", "ह": "h",
}
VOWELS = {  # independent vowels and vowel signs
    "अ": "a", "आ": "a", "इ": "i", "ई": "i", "उ": "u", "ऊ": "u", "ऋ": "r", "ए": "e", "ऐ": "e", "ओ": "o", "औ": "o",
    "ऍ": "e", "ऑ": "o", "ा": "a", "ि": "i", "ी": "i", "ु": "u", "ू": "u", "ृ": "r", "े": "e", "ै": "e",
    "ो": "o", "ौ": "o", "ॅ": "e", "ॉ": "o",
}
NASALS = {"ं", "ँ"}


def indic_sounds(word: str) -> str:
    """Rough sounds of a Hindi/Gujarati word: consonant classes and spoken vowels
    (the unwritten 'a' after a consonant is left out, as speech often drops it)."""
    out = []
    for ch in word:
        cp = ord(ch)
        if 0x0A80 <= cp <= 0x0AFF:
            ch = chr(cp - GUJARATI_TO_DEVANAGARI)
        if ch in CONSONANTS:
            out.append(CONSONANTS[ch])
        elif ch in VOWELS:
            out.append(VOWELS[ch])
        elif ch in NASALS:
            out.append("n")
        elif ch == "ः":
            out.append("h")
    return "".join(out)


# English spelling -> the same sound classes, most specific rules first.
_EN_RULES = [
    # Capitals are finished sounds later rules must not touch ("C": the ch sound).
    (r"tion|sion", "san"), (r"ture", "Car"), (r"ctu", "kCu"), (r"d?ge$", "J"), (r"ough", "o"), (r"augh", "a"),
    (r"igh", "i"), (r"gh", ""), (r"^kn", "n"), (r"^wr", "r"), (r"mb$", "m"), (r"ck", "k"), (r"ph", "p"),
    (r"tch|sh|ch", "C"), (r"th", "t"), (r"wh", "v"), (r"qu", "kv"), (r"x", "ks"), (r"c(?=[eiy])", "s"), (r"c", "k"),
    (r"q", "k"), (r"z", "j"), (r"ee|ea|ie", "i"), (r"oo|ou|ow", "u"), (r"ai|ay|ey", "e"), (r"au|aw", "o"),
    (r"w", "v"), (r"f", "p"), (r"^y", "Y"), (r"y", "i"),
]


def english_sounds(word: str) -> str:
    w = re.sub(r"[^a-z]", "", word.lower())
    if w == "i":
        return "ai"
    if len(w) > 3 and w.endswith("e") and w[-2] not in "aeiouy":  # silent final e ("stage", "home")
        w = w[:-1] if not w.endswith("ge") else w
    for pattern, sound in _EN_RULES:
        w = re.sub(pattern, sound, w)
    w = re.sub(r"(.)\1+", r"\1", w.lower())  # doubled letters sound once ("Y": a leading y stays y)
    # "sh"/"ch" both became "c"; Gujarati writes "sh" with શ (s), so either matches below.
    return w


VOWEL_SET = set("aeiou")
# Sounds that are spelled differently across the two but often the same sound.
CLOSE = [set("td"), set("kg"), set("pb"), set("sc"), set("cj"), set("sj"), set("vb"), set("nm"), set("rl")]


def _cost(a: str, b: str) -> float:
    if a == b:
        return 0.0
    if a in VOWEL_SET and b in VOWEL_SET:
        return 0.3
    if a in VOWEL_SET or b in VOWEL_SET:
        return 1.0
    return 0.5 if any(a in c and b in c for c in CLOSE) else 1.0


def _weight(ch: str) -> float:
    return 0.4 if ch in VOWEL_SET else 1.0


def sound_similarity(a: str, b: str) -> float:
    """0-1: how alike two sound strings are (vowels count less than consonants)."""
    if not a or not b:
        return 0.0
    prev = [0.0]
    for ch in b:
        prev.append(prev[-1] + _weight(ch))
    for ca in a:
        cur = [prev[0] + _weight(ca)]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + _weight(ca), cur[j - 1] + _weight(cb), prev[j - 1] + _cost(ca, cb)))
        prev = cur
    total = max(sum(map(_weight, a)), sum(map(_weight, b)))
    return max(0.0, 1.0 - prev[-1] / total)



def _score(a: str, b: str) -> float:
    """Alignment score of two sounds: positive when alike."""
    if a == b:
        return 1.0 if a not in VOWEL_SET else 0.5
    if a in VOWEL_SET and b in VOWEL_SET:
        return 0.1
    if a in VOWEL_SET or b in VOWEL_SET:
        return -1.0
    return 0.4 if any(a in c and b in c for c in CLOSE) else -1.0


def local_match(a: str, b: str) -> tuple[float, int, int, int, int]:
    """The best-matching stretches of two sound strings (Smith-Waterman):
    (score, a_start, a_end, b_start, b_end), ends exclusive. Finds an English
    sentence spelled in Gujarati letters inside a longer Gujarati line, and the
    part of Whisper's sentence that was really said in English."""
    best = (0.0, 0, 0, 0, 0)
    prev = [0.0] * (len(b) + 1)
    prev_from = [(0, 0)] * (len(b) + 1)  # where each cell's stretch started
    for i in range(1, len(a) + 1):
        cur, cur_from = [0.0], [(i, 0)]
        for j in range(1, len(b) + 1):
            gap_a = 0.3 if a[i - 1] in VOWEL_SET else 0.7
            gap_b = 0.3 if b[j - 1] in VOWEL_SET else 0.7
            options = [
                (0.0, (i, j)),
                (prev[j - 1] + _score(a[i - 1], b[j - 1]), prev_from[j - 1]),
                (prev[j] - gap_a, prev_from[j]),
                (cur[j - 1] - gap_b, cur_from[j - 1]),
            ]
            score, start = max(options, key=lambda o: o[0])
            if score == 0.0:
                start = (i, j)
            cur.append(score)
            cur_from.append(start)
            if score > best[0]:
                best = (score, start[0], i, start[1], j)
        prev, prev_from = cur, cur_from
    return best


# --------------------------------------------------------------------------- #
# Which words are English
# --------------------------------------------------------------------------- #

# Real English words that are also how Whisper writes common Hindi/Gujarati
# words in Latin letters, or how it translates them ("મમ્મી" -> "mom").
# Inside an English phrase they're fine ("I want to go").
NOT_ENGLISH_ALONE = {
    "na", "se", "jo", "to", "so", "ha", "ho", "mana", "kari", "karen", "mummy", "mommy", "mom", "papa", "mama",
    "dada", "nana", "bhai", "hai", "ka", "ki", "ke", "re", "are", "bas", "ali", "kya", "at", "is", "a", "an", "the",
    # Gujarati words that sound like their English translation (અને/and, ફૂલ/full)
    # or like an unrelated English word (ગોરી "fair" / gory).
    "and", "full", "gory", "gori",
}
# Indian names said as Gujarati words in Gujarati ("તમે ગુજરાતી છો"): only
# written in English inside an English phrase ("do a Gujarati film").
NATIVE_NAMES = {
    "gujarati", "gujarat", "hindi", "india", "indian", "bombay", "mumbai", "ahmedabad", "surat", "baroda", "vadodara",
    "rajkot", "delhi", "krishna", "ram", "rama", "shiva", "ganesh", "diwali", "holi", "navratri", "jai", "shri",
}
_SUFFIXES = ["'s", "s", "es", "ed", "d", "ing", "ly", "er", "ers", "est", "ies", "ied", "ness", "ment", "ally"]


@lru_cache(maxsize=1)
def english_words() -> frozenset[str]:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "english-words.txt")
    try:
        with open(path, encoding="utf-8") as f:
            return frozenset(w.strip().lower() for w in f if w.strip() and not w.startswith("#"))
    except OSError:
        return frozenset()


def is_english(word: str) -> bool:
    """A real English word (the bundled dictionary, with common endings)."""
    w = re.sub(r"[^a-z']", "", word.lower()).strip("'")
    if not w:
        return False
    words = english_words()
    if w in words:
        return True
    for suf in _SUFFIXES:
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            stem = w[: -len(suf)]
            if stem in words or stem + "e" in words or (suf in ("ies", "ied") and stem + "y" in words):
                return True
            if len(stem) > 3 and stem[-1] == stem[-2] and stem[:-1] in words:  # "stopped"
                return True
    return False


def _key(word: str) -> str:
    return re.sub(r"[^a-z']", "", word.lower()).strip("'")


# --------------------------------------------------------------------------- #
# Combining
# --------------------------------------------------------------------------- #

# A Gujarati word and English words this alike are the same speech.
SAME_SOUND = 0.72
# Short words (up to two consonants) match by chance more easily.
SAME_SOUND_SHORT = 0.85
# An English phrase must need each of its words: without one it must score this much less.
EVERY_WORD = 0.03
# Between two replaced English words, up to this many Gujarati words become the
# English Whisper heard between them ("can બી ધૂ યુ like" -> "can be the... Would you like").
BETWEEN_MAX = 3
# Whisper's confidence in English it alone heard (where IndicConformer wrote nothing).
RUN_MIN_WORD = 0.6
RUN_MIN_MEAN = 0.85
# Shorter confident runs were Whisper's translation of Gujarati ("don't believe in").
RUN_MIN_WORDS = 4
# Time slack between the two models' word times (s).
SLACK = 0.6
# IndicConformer's words are short and packed; a pause between them shorter
# than this is still its speech, not something it left out.
GAP = 0.8

# Sentences (`_match_sentences`): at least this many English words, a pause this
# long ends one, Gujarati words this far outside its time are still considered,
# and this sound similarity makes the Gujarati the same sentence (calibrated on
# the user's test meeting; see test_mixed.py).
SENTENCE_MIN_WORDS = 3
SENTENCE_PAUSE = 0.8
SENTENCE_SLACK = 1.0
SENTENCE_SAME = 0.62

# Longest phrases matched at once. Longer ones (4 Gujarati / 6 English) let
# common short words match by chance ("છે" -> "She").
MAX_INDIC_WORDS = 2
MAX_ENGLISH_WORDS = 3
# The commonest Gujarati and Hindi words: never English on their own (they
# sound like short English words: છે/"she", એટલે/"at least"). Inside an English
# phrase they can still become Whisper's words (`_fill_between`).
COMMON_INDIC = {
    "છે", "છો", "છું", "છીએ", "હતું", "હતો", "હતી", "તો", "એટલે", "એકદમ", "અને", "પણ", "કે", "ને", "ના", "નો", "ની", "નું",
    "મને", "હું", "તમે", "તું", "એ", "આ", "જ", "હા", "શું", "કેમ", "ક્યાં", "પછી", "બી", "કંઈ", "નથી", "નહીં", "નહિ", "થી", "માં",
    "મારા", "મારી", "મારો", "મારું", "એનું", "એની", "એના", "એનો", "તમારા", "તમારી", "આપણે", "એમ", "એમને", "એને", "તોય",
    "है", "हैं", "था", "थी", "तो", "और", "कि", "के", "का", "की", "में", "से", "हाँ", "हां", "नहीं", "भी", "यह", "वह", "मैं",
    "तुम", "आप", "क्या", "को", "पर", "ही", "हम",
}
# Short English words that are mostly what a common Gujarati word sounds like.
NOT_ENGLISH_ALONE_EXTRA = {"she", "so", "my", "them", "he", "me", "we", "us", "it", "i", "i'd"}

# Gujarati/Hindi endings that attach to English words ("સિટીથી" = "from the city").
ENDINGS = ["માંથી", "થી", "માં", "નો", "ની", "નું", "ને", "ના", "નાં", "વાળા", "મેં", "से", "में", "का", "की", "के", "को"]


def _forms(words: list[dict], i: int) -> list[tuple[int, str]]:
    """(how many Gujarati words, ending left on the last one) to try at `i`.
    Several words can be one English word or phrase ("લવ સ્ટોરી")."""
    forms = []
    for n in range(MAX_INDIC_WORDS, 0, -1):
        if i + n > len(words) or any(w["lang"] == "en" or w["w"] in COMMON_INDIC for w in words[i : i + n]):
            continue
        last = words[i + n - 1]["w"]
        forms.append((n, ""))
        forms += [(n, end) for end in ENDINGS if last.endswith(end) and len(last) - len(end) >= 2]
    return forms


def _clean(word: str) -> str:
    return re.sub(r"^[^\w']+|[^\w']+$", "", word)


def _consonants(sounds: str) -> int:
    return sum(ch not in VOWEL_SET for ch in sounds)


def _phrase_score(sounds: str, words: list[dict]) -> float:
    return sound_similarity(sounds, "".join(english_sounds(e["w"]) for e in words))


def _best_match(out: list[dict], i: int, english: list[dict], used: set[int]):
    """Best (score, n_indic, first, last English index, ending) for the Gujarati
    word(s) at `i`, or None."""
    best = None
    for n, ending in _forms(out, i):
        span = out[i : i + n]
        texts = [w["w"] for w in span]
        texts[-1] = texts[-1][: len(texts[-1]) - len(ending)]
        parts = [indic_sounds(t) for t in texts]
        sounds = "".join(parts)
        if not sounds:
            continue
        need = SAME_SOUND_SHORT if _consonants(sounds) <= 2 else SAME_SOUND
        s0, s1 = span[0]["s"] - SLACK, span[-1]["e"] + SLACK
        near = [j for j, e in enumerate(english) if j not in used and e["e"] >= s0 and e["s"] <= s1]
        for a in range(len(near)):
            for b in range(a, min(a + MAX_ENGLISH_WORDS, len(near))):
                js = near[a : b + 1]
                if js != list(range(js[0], js[-1] + 1)):
                    continue
                words = [english[j] for j in js]
                keys = [_key(e["w"]) for e in words]
                if not all(is_english(k) for k in keys):
                    continue
                ps = [e["p"] for e in words]
                if min(ps) < 0.3 or sum(ps) / len(ps) < 0.5:
                    continue
                # Alone, Indian names and words that sound like their own translation
                # stay Gujarati; an Indian name only switches inside an English phrase.
                if all(k in NATIVE_NAMES or k in NOT_ENGLISH_ALONE or k in NOT_ENGLISH_ALONE_EXTRA for k in keys):
                    continue
                if len(keys) < 3 and any(k in NATIVE_NAMES for k in keys):
                    continue
                en_sounds = "".join(english_sounds(e["w"]) for e in words)
                if not 0.6 <= len(en_sounds) / max(1, len(sounds)) <= 1.6:
                    continue
                score = sound_similarity(sounds, en_sounds)
                if score < need or (best is not None and score <= best[0]):
                    continue
                # Each English word must be needed ("ગુજરાતી" is "Gujarat?", not "Gujarat? Yeah,").
                if len(words) > 1 and max(_phrase_score(sounds, words[1:]), _phrase_score(sounds, words[:-1])) >= score - EVERY_WORD:
                    continue
                # ...and each Gujarati word (a Gujarati word next to the English stays).
                if n > 1 and not ending and max(
                    sound_similarity("".join(parts[1:]), en_sounds), sound_similarity("".join(parts[:-1]), en_sounds)
                ) >= score - EVERY_WORD:
                    continue
                best = (score, n, js[0], js[-1], ending)
    return best


def _word(e: dict, j: int, s: float | None = None, end: float | None = None) -> dict:
    w = _clean(e["w"]) or e["w"]
    if len(w) > 3 and w.isupper():  # Whisper sometimes SHOUTS
        w = w.lower()
    return {"w": w, "s": e["s"] if s is None else s, "e": e["e"] if end is None else end, "lang": "en", "j": j}


def _replace(out: list[dict], i: int, english: list[dict], used: set[int], match) -> int:
    """Put the matched English in place of the Gujarati word(s); returns how many words it is."""
    _, n, j, k, ending = match
    span = out[i : i + n]
    lo, hi = span[0]["s"], span[-1]["e"]
    repl = []
    for x in range(j, k + 1):
        e = english[x]
        # Times kept inside the Gujarati words' span, so the order stays right.
        s = min(max(e["s"], lo), hi)
        repl.append(_word(e, x, s, max(s, min(max(e["e"], lo), hi))))
    repl[-1]["w"] += ending  # "Cityથી": the Gujarati ending stays on the English word
    out[i : i + n] = repl
    used.update(range(j, k + 1))
    return len(repl)


def _fill_between(out: list[dict], english: list[dict], used: set[int]) -> None:
    """A few Gujarati words left between two replaced English words become the
    English Whisper heard between those two ("can બી ધૂ યુ like" -> "can be the...
    Would you like"): inside an English phrase, IndicConformer's leftovers are
    English it spelled by sound."""
    i = 0
    while i < len(out):
        if out[i]["lang"] != "en":
            i += 1
            continue
        k = i + 1
        while k < len(out) and out[k]["lang"] != "en":
            k += 1
        if k >= len(out) or not 1 <= k - i - 1 <= BETWEEN_MAX:
            i = k
            continue
        jl, jr = out[i]["j"], out[k]["j"]
        gap = list(range(jl + 1, jr))
        words = [english[j] for j in gap]
        between = out[i + 1 : k]
        # Everyday Gujarati words there (એટલે મારા) and Whisper's translation of
        # them ("So my") don't sound alike; English spelled by sound (ટુ ડુ અ) does.
        if any(w["w"] in COMMON_INDIC for w in between) and sound_similarity(
            "".join(indic_sounds(w["w"]) for w in between), "".join(english_sounds(e["w"]) for e in words)
        ) < SAME_SOUND:
            i = k
            continue
        if gap and not any(j in used for j in gap) and all(is_english(_key(e["w"])) and e["p"] >= 0.5 for e in words):
            lo, hi = out[i]["e"], out[k]["s"]
            out[i + 1 : k] = [_word(english[j], j, min(max(english[j]["s"], lo), hi), min(max(english[j]["e"], lo), hi)) for j in gap]
            used.update(gap)
            k = i + 1 + len(gap)
        i = k


def sentences(english: list[dict]) -> list[list[int]]:
    """Whisper's words grouped into sentences (indices): at . ? ! or a pause."""
    out: list[list[int]] = [[]]
    for j, e in enumerate(english):
        out[-1].append(j)
        pause = j + 1 < len(english) and english[j + 1]["s"] - e["e"] > SENTENCE_PAUSE
        if e["w"].rstrip("\"'").endswith((".", "?", "!", "…")) or pause:
            out.append([])
    return [s for s in out if s]


def _sounds_of(words: list[dict], sounder) -> tuple[str, list[int]]:
    """Sounds of the words joined, and which word each sound belongs to."""
    text, owner = "", []
    for k, w in enumerate(words):
        s = sounder(w["w"])
        text += s
        owner += [k] * len(s)
    return text, owner


DEBUG = bool(os.environ.get("VD_DEBUG_MIXED"))


def _match_sentences(out: list[dict], english: list[dict], used: set[int]) -> None:
    """English sentences spelled in Gujarati letters -> Whisper's sentence.

    Word by word, short words (ટુ, ડુ, અ) don't match on their own and the line
    stays half Gujarati letters ("કેન બી ધ વુડ you like ટુ ડુ અ ગુજરાતી film").
    A whole sentence does: its sounds follow Whisper's English closely, while a
    Gujarati sentence and Whisper's translation of it don't. Only the part of
    Whisper's sentence that matches is taken (it may also hold a translation)."""
    for sent in sentences(english):
        js = [j for j in sent if j not in used]
        if len(js) < SENTENCE_MIN_WORDS:
            continue
        s0, s1 = english[js[0]]["s"] - SENTENCE_SLACK, english[js[-1]]["e"] + SENTENCE_SLACK
        idx = [i for i, w in enumerate(out) if w["lang"] != "en" and w["e"] >= s0 and w["s"] <= s1]
        if not idx:
            continue
        a, a_owner = _sounds_of([out[i] for i in idx], indic_sounds)
        b, b_owner = _sounds_of([english[j] for j in js], english_sounds)
        if not a or not b:
            continue
        _, a0, a1, b0, b1 = local_match(a, b)
        if a1 <= a0 or b1 <= b0:
            continue
        first, last = idx[a_owner[a0]], idx[a_owner[a1 - 1]]
        span_en = js[b_owner[b0] : b_owner[b1 - 1] + 1]
        words = [english[j] for j in span_en]
        span = out[first : last + 1]
        if len(words) < SENTENCE_MIN_WORDS or any(w["lang"] == "en" for w in span):
            continue
        keys = [_key(e["w"]) for e in words]
        english_share = sum(is_english(k) for k in keys) / len(keys)
        mean_p = sum(e["p"] for e in words) / len(words)
        score = sound_similarity("".join(indic_sounds(w["w"]) for w in span), "".join(english_sounds(e["w"]) for e in words))
        # A Gujarati sentence full of loanwords sounds like its translation ("મારા
        # ડેડ તો ગુજરાતી છે બોમ્બે" / "my dad is Gujarati, Bombay"); its everyday
        # Gujarati words (છે, તો, મારા) give it away.
        gujarati_glue = sum(w["w"] in COMMON_INDIC for w in span)
        ok = score >= SENTENCE_SAME and english_share >= 0.8 and mean_p >= 0.5 and gujarati_glue <= 1
        if DEBUG:
            print(f"[mixed] {'TAKE' if ok else 'skip'} {score:.2f} p={mean_p:.2f} en={english_share:.2f} | "
                  f"{' '.join(w['w'] for w in span)} | {' '.join(e['w'] for e in words)}", file=sys.stderr)
        if ok:
            out[first : last + 1] = [dict(_word(e, j), w=e["w"]) for j, e in zip(span_en, words)]
            used.update(span_en)


def merge(indic_words: list[dict], english: list[dict]) -> list[dict]:
    """Combine IndicConformer's words with Whisper's forced-English words.

    `indic_words`: [{"w", "s", "e"}]; `english`: [{"w", "s", "e", "p"}] (p:
    Whisper's word probability). Times in seconds, same origin. Returns the
    words in order, each with "w", "s", "e" and "lang" ("en" for English)."""
    out = [dict(w, lang="indic") for w in indic_words]
    used: set[int] = set()

    # 0. Whole English sentences spelled in Gujarati letters.
    _match_sentences(out, english, used)

    # 1. Gujarati words spelled by sound -> the English heard at that moment.
    i = 0
    while i < len(out):
        match = _best_match(out, i, english, used)
        i += _replace(out, i, english, used, match) if match else 1

    # 2. Gujarati leftovers inside an English phrase.
    _fill_between(out, english, used)

    # 3. English that IndicConformer dropped: confident runs where it wrote nothing.
    covered: list[list[float]] = []
    for w in sorted(out, key=lambda w: w["s"]):
        if covered and w["s"] - covered[-1][1] < GAP:
            covered[-1][1] = max(covered[-1][1], w["e"])
        else:
            covered.append([w["s"], w["e"]])

    def free(e: dict) -> bool:
        mid = (e["s"] + e["e"]) / 2
        return not any(a - 0.15 <= mid <= b + 0.15 for a, b in covered)

    runs: list[list[int]] = [[]]
    for j, e in enumerate(english):
        if j not in used and free(e) and is_english(_key(e["w"])) and e["p"] >= RUN_MIN_WORD:
            runs[-1].append(j)
        elif runs[-1]:
            runs.append([])
    for r in runs:
        ps = [english[j]["p"] for j in r]
        if len(r) >= RUN_MIN_WORDS and sum(ps) / len(ps) >= RUN_MIN_MEAN:
            at = next((x for x, w in enumerate(out) if w["s"] > english[r[0]]["s"]), len(out))
            # Whole sentences keep Whisper's punctuation.
            out[at:at] = [dict(_word(english[j], j), w=english[j]["w"]) for j in r]
    for w in out:
        w.pop("j", None)
    return out


def join_words(words: list[dict]) -> str:
    return " ".join(w["w"] for w in words).strip()
