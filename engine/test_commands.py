"""Run: python engine/test_commands.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from commands import is_bare_command, parse  # noqa: E402

CMDS = {
    "stop": "stop",
    "pause": "pause",
    "resume": "resume",
    "record_tasks": "record task, record tasks",
    "tasks_recorded": "task recorded, tasks recorded",
}


def p(text: str, name: str = "Jarvis"):
    parts = parse(text, name, CMDS)
    for part in parts:
        a, b = part.pop("span")
        assert 0 <= a <= b <= len(text), (text, a, b)
    return parts


def cmd(c):
    return {"type": "command", "command": c}


def txt(t):
    return {"type": "text", "text": t}


CASES = [
    # plain commands, with the punctuation Whisper tends to add
    ("Jarvis stop.", [cmd("stop")]),
    ("Jarvis, pause.", [cmd("pause")]),
    ("jarvis resume", [cmd("resume")]),
    ("Jarvis, record tasks.", [cmd("record_tasks")]),
    ("Jarvis record task", [cmd("record_tasks")]),
    ("Jarvis, tasks recorded.", [cmd("tasks_recorded")]),
    ("Jarvis task recorded", [cmd("tasks_recorded")]),
    # text around commands
    ("Send the report to Priya. Jarvis pause.", [txt("Send the report to Priya."), cmd("pause")]),
    ("Jarvis resume. I think we should ship it.", [cmd("resume"), txt("I think we should ship it.")]),
    ("Okay that's all, Jarvis stop", [txt("Okay that's all"), cmd("stop")]),
    # fillers and ASR mishearings
    ("Jarvis, please stop.", [cmd("stop")]),
    ("Jervis stop", [cmd("stop")]),
    ("Jar vis, pause", [cmd("pause")]),
    ("Jarvis, record the tasks", [txt("Jarvis, record the tasks")]),  # "the" is not a filler -> text
    ("Jarvis, tasks recorded. Jarvis stop.", [cmd("tasks_recorded"), cmd("stop")]),
    # the name without a command is ordinary text
    ("I watched Jarvis in Iron Man.", [txt("I watched Jarvis in Iron Man.")]),
    ("Jarvis is my assistant", [txt("Jarvis is my assistant")]),
    # command words without the name are ordinary text
    ("Please stop the build and pause the deploy.", [txt("Please stop the build and pause the deploy.")]),
    # custom name
    ("Friday, stop.", [cmd("stop")], "Friday"),
    ("Hey Nova pause", [cmd("pause")], "Hey Nova"),
    ("", []),
]


def main() -> None:
    failed = 0
    for case in CASES:
        text, expected = case[0], case[1]
        name = case[2] if len(case) > 2 else "Jarvis"
        got = p(text, name)
        if got != expected:
            failed += 1
            print(f"FAIL {text!r}\n  expected {expected}\n  got      {got}")
    for text, bare in [("Resume", True), ("Record tasks.", True), ("Please resume the build", False), ("Jarvis resume", False)]:
        if is_bare_command(text, CMDS) != bare:
            failed += 1
            print(f"FAIL is_bare_command({text!r}) != {bare}")
    for check in (check_collapse_repeats, check_echoes_vocabulary, check_idle_watchdog):
        try:
            check()
        except AssertionError as e:
            failed += 1
            print(f"FAIL {check.__name__}: {e}")
    total = len(CASES) + 4 + 3
    print(f"{total - failed}/{total} passed" if failed else f"all {total} passed")
    raise SystemExit(1 if failed else 0)


def check_collapse_repeats() -> None:
    from speech import collapse_repeats

    for text, expected in [
        ("I don't know, I don't know, I don't know.", "I don't know."),
        ("Hello, hello, hello", "Hello, hello, hello"),  # a word 3 times is kept
        ("no no no no no", "no"),
        ("હા હા હા હા હા છે", "હા છે"),
        ("Send it today.", "Send it today."),
        ("", ""),
    ]:
        assert collapse_repeats(text) == expected, (text, collapse_repeats(text))


def check_echoes_vocabulary() -> None:
    from speech import echoes_vocabulary

    vocab = "Jarvis, Priya, Voice Desk"
    assert echoes_vocabulary("Priya, Voice Desk.", vocab)
    assert not echoes_vocabulary("Send the report to Priya.", vocab)
    assert not echoes_vocabulary("Priya", vocab)  # one word: too little to tell
    assert not echoes_vocabulary("Priya, Voice Desk.", None)


def check_idle_watchdog() -> None:
    """The engine only exits when idle: not while a request (a long meeting)
    is running, or dictation is on, however long ago Whisper was last used."""
    import time

    import engine

    saved = engine.idle_unload_s, engine.busy, engine.last_done, engine.transcriber.model, engine.transcriber.last_used
    try:
        now = time.time()
        engine.idle_unload_s = 600
        engine.transcriber.model = object()  # loaded
        engine.transcriber.last_used = engine.last_done = now - 700
        engine.busy = 1
        assert not engine.idle_too_long(now), "exited during a request"
        engine.busy = 0
        assert engine.idle_too_long(now)
        engine.last_done = now - 60  # a request just ended
        assert not engine.idle_too_long(now), "exited right after a request"
        engine.last_done = now - 700
        engine.streams[-1] = None  # dictation on
        assert not engine.idle_too_long(now), "exited while dictating"
        del engine.streams[-1]
        engine.idle_unload_s = 0  # "never unload"
        assert not engine.idle_too_long(now)
    finally:
        engine.streams.pop(-1, None)
        (engine.idle_unload_s, engine.busy, engine.last_done, engine.transcriber.model,
         engine.transcriber.last_used) = saved


if __name__ == "__main__":
    main()
