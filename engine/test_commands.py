"""Run: python engine/test_commands.py"""

from commands import is_bare_command, parse

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
    print(f"{len(CASES) - failed}/{len(CASES)} parse cases passed" if failed else f"all {len(CASES) + 4} passed")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
