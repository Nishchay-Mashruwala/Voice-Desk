"""Voice command parsing: "<assistant name> <command phrase>" inside dictated text.

Speech recognition is imperfect ("Jarvis" may come out as "Jarvis," "Jervis",
"Travis"), so both the name and the phrase are matched fuzzily word by word.
A name *without* a known command after it is ordinary text and is left alone
("I watched Jarvis in Iron Man" is typed as-is).
"""

from __future__ import annotations

import re
from difflib import SequenceMatcher

WORD = re.compile(r"[\w']+", re.UNICODE)
# Words people naturally insert between the name and the command.
FILLERS = {"please", "now", "ok", "okay", "hey", "just", "can", "you", "could", "go", "and"}
MAX_FILLERS = 2


def _similar(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()


def _word_matches(heard: str, expected: str) -> bool:
    if heard == expected:
        return True
    # Short words must match exactly-ish; long words tolerate a letter or two.
    threshold = 0.9 if len(expected) <= 3 else 0.75
    return _similar(heard, expected) >= threshold


def _split_phrases(phrases: str | list[str]) -> list[list[str]]:
    if isinstance(phrases, str):
        phrases = phrases.split(",")
    out = []
    for p in phrases:
        words = [w.lower() for w in WORD.findall(p)]
        if words:
            out.append(words)
    return out


def _tidy(text: str, capitalize: bool = False) -> str:
    if not WORD.search(text):
        return ""  # only punctuation left between/around commands
    text = text.strip().strip(",;:-–— ").strip()
    if capitalize and text:
        text = text[0].upper() + text[1:]
    return text


def _match_name(words: list[str], i: int, name: list[str]) -> int:
    """Number of words consumed if the assistant name starts at words[i], else 0."""
    # Normal case: "jarvis" as one word (or "hey jarvis" for multi-word names).
    if i + len(name) <= len(words) and all(_word_matches(words[i + k], name[k]) for k in range(len(name))):
        return len(name)
    # ASR sometimes splits a name: "jar vis". Both halves must be fragments,
    # otherwise "all jarvis" would count as a split name.
    if len(name) == 1 and i + 1 < len(words):
        a, b = words[i], words[i + 1]
        if len(a) < len(name[0]) and len(b) < len(name[0]) and _similar(a + b, name[0]) >= 0.85:
            return 2
    return 0


def parse(text: str, name: str, commands: dict[str, str | list[str]]) -> list[dict]:
    """Split an utterance into ordered parts.

    Returns e.g. [{"type": "text", "text": "Send the report", "span": [0, 16]},
                  {"type": "command", "command": "pause", "span": [17, 30]}].
    `span` is the part's character range in `text` (used to attach word timings).
    `commands` maps command id -> comma-separated phrases ("record task, record tasks").
    """
    name_words = [w.lower() for w in WORD.findall(name)]
    table = [(cid, phrase) for cid, phrases in commands.items() for phrase in _split_phrases(phrases)]
    # Prefer the longest phrase when several match ("tasks recorded" over "task").
    table.sort(key=lambda item: -len(item[1]))

    tokens = [(m.group().lower(), m.start(), m.end()) for m in WORD.finditer(text)]
    words = [t[0] for t in tokens]
    if not name_words or not table:
        return [{"type": "text", "text": text.strip(), "span": [0, len(text)]}] if text.strip() else []

    parts: list[dict] = []
    text_start = 0  # char offset where pending plain text begins
    i = 0
    while i < len(words):
        consumed = _match_name(words, i, name_words)
        if not consumed:
            i += 1
            continue
        j = i + consumed
        match = None
        for skip in range(MAX_FILLERS + 1):
            if skip and (j + skip - 1 >= len(words) or words[j + skip - 1] not in FILLERS):
                break
            k = j + skip
            for cid, phrase in table:
                if k + len(phrase) <= len(words) and all(
                    _word_matches(words[k + n], phrase[n]) for n in range(len(phrase))
                ):
                    match = (cid, k + len(phrase))
                    break
            if match:
                break
        if not match:
            i += 1
            continue
        cid, end_word = match
        before = _tidy(text[text_start : tokens[i][1]], capitalize=not parts)
        if before:
            parts.append({"type": "text", "text": before, "span": [text_start, tokens[i][1]]})
        parts.append({"type": "command", "command": cid, "span": [tokens[i][1], tokens[end_word - 1][2]]})
        text_start = tokens[end_word - 1][2]
        i = end_word

    rest = text[text_start:]
    if parts:
        # Drop the punctuation Whisper puts right after a command ("Jarvis pause. Hello").
        rest = rest.lstrip(" .,!?;:")
        rest = _tidy(rest, capitalize=True)
    else:
        rest = rest.strip()
    if rest:
        parts.append({"type": "text", "text": rest, "span": [text_start, len(text)]})
    return parts


def is_bare_command(text: str, commands: dict[str, str | list[str]]) -> bool:
    """True if the whole utterance is just a command phrase without the name."""
    words = [w.lower() for w in WORD.findall(text)]
    return any(
        len(words) == len(phrase) and all(_word_matches(words[n], phrase[n]) for n in range(len(phrase)))
        for phrases in commands.values()
        for phrase in _split_phrases(phrases)
    )
