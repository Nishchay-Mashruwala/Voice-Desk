"""End-to-end check of live streaming: feeds a WAV to the engine in real time.

  python engine/test_stream.py <audio.wav> [voice_profile.npy] [speed]

Prints each utterance event and the latency from end-of-speech to text.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import threading
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    path = sys.argv[1]
    profile = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
    speed = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
    vocab = sys.argv[4] if len(sys.argv) > 4 else "Jarvis, Priya, Voice Desk"
    with wave.open(path, "rb") as w:
        pcm = w.readframes(w.getnframes())

    proc = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "engine.py")],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8",
    )
    t0 = time.time()
    events = []

    def reader() -> None:
        for line in proc.stdout:
            msg = json.loads(line)
            msg["_t"] = round(time.time() - t0, 2)
            events.append(msg)
            if msg.get("event") == "utterance":
                lag = msg["_t"] - msg["end"] / speed
                print(f"[{msg['_t']:6.2f}s] {msg['start']:.1f}-{msg['end']:.1f} lag={lag:.2f}s score={msg['score']} "
                      f"{json.dumps(msg['parts'], ensure_ascii=False)}", flush=True)
            elif msg.get("event") in ("stream_ready", "stream_error"):
                print(f"[{msg['_t']:6.2f}s] {msg}", flush=True)

    threading.Thread(target=reader, daemon=True).start()

    def send(obj: dict) -> None:
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    send({
        "id": 1, "cmd": "stream_start", "sid": 7, "vocabulary": vocab,
        "wake_name": "Jarvis", "voice_profile": profile,
        "languages": os.environ.get("VD_LANGS", "en").split(","), "translate": ([t for t in os.environ.get("VD_TRANSLATE", "").split(",") if t] or False),
        "prefer": os.environ.get("VD_PREFER"),
        "commands": {"stop": "stop", "pause": "pause", "resume": "resume",
                     "record_tasks": "record task, record tasks", "tasks_recorded": "task recorded, tasks recorded"},
    })
    # Wait for the model so timing reflects steady-state latency.
    while not any(e.get("event") == "stream_ready" for e in events):
        time.sleep(0.05)
    t0 = time.time()
    chunk = 1600 * 2  # 100 ms of s16 mono
    for i in range(0, len(pcm), chunk):
        send({"cmd": "audio", "sid": 7, "pcm": base64.b64encode(pcm[i : i + chunk]).decode()})
        time.sleep(0.1 / speed)
    send({"id": 2, "cmd": "stream_stop", "sid": 7})
    while not any(e.get("id") == 2 for e in events):
        time.sleep(0.05)
    print(f"stopped after {time.time() - t0:.2f}s (audio {len(pcm) / 32000 / speed:.2f}s)")
    proc.stdin.close()
    proc.wait(timeout=10)


if __name__ == "__main__":
    main()
