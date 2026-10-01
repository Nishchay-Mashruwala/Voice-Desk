"""How much RAM, CPU and GPU memory each Voice Desk job uses on this computer.

Runs the speech engine the way the app does (a subprocess speaking JSON lines)
on a meeting recording, then asks the task AI (Ollama) about its transcript,
sampling resources 4 times a second. Prints one row per job.

  .venv/Scripts/python engine/bench_resources.py MIC.wav SYSTEM.wav [--device auto|cuda|cpu]

Settings (languages, Hugging Face token, model names) come from the app's
database, like a real run. GPU memory is the whole GPU's use minus what was in
use before starting, so close other GPU-heavy apps first.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.request
import wave

import psutil

HERE = os.path.dirname(os.path.abspath(__file__))
DB = {
    "win32": os.path.expandvars(r"%APPDATA%\com.rajvee.voicedesk\voicedesk.db"),
    "darwin": os.path.expanduser("~/Library/Application Support/com.rajvee.voicedesk/voicedesk.db"),
}.get(sys.platform, os.path.expanduser("~/.local/share/com.rajvee.voicedesk/voicedesk.db"))


def app_settings() -> dict:
    try:
        row = sqlite3.connect(DB).execute("SELECT value FROM settings WHERE key = 'app'").fetchone()
        return json.loads(row[0]) if row else {}
    except Exception:  # noqa: BLE001
        return {}


class Gpu:
    """Total NVIDIA GPU memory in use and utilisation, streamed by nvidia-smi."""

    def __init__(self) -> None:
        self.mem_mb = self.util = 0.0
        self.ok = shutil.which("nvidia-smi") is not None
        if not self.ok:
            return
        self.proc = subprocess.Popen(
            ["nvidia-smi", "--query-gpu=memory.used,utilization.gpu", "--format=csv,noheader,nounits", "-lms", "250"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        threading.Thread(target=self._read, daemon=True).start()
        time.sleep(1.0)

    def _read(self) -> None:
        for line in self.proc.stdout:
            try:
                parts = [float(x) for x in line.split(",")[:2]]
            except ValueError:
                continue
            self.mem_mb = sum(parts[:1])  # first GPU
            self.util = parts[1] if len(parts) > 1 else 0.0


class Meter:
    """Peaks for the current job: RAM and CPU of a process tree, GPU memory above the starting level."""

    def __init__(self, gpu: Gpu) -> None:
        self.gpu = gpu
        self.gpu_base = gpu.mem_mb
        self.procs: list[psutil.Process] = []
        # psutil reports CPU use since the previous call on the same object, so keep them.
        self.known: dict[int, psutil.Process] = {}
        self.rows: list[dict] = []
        self.job: dict | None = None
        self.lock = threading.Lock()
        threading.Thread(target=self._run, daemon=True).start()

    def start(self, name: str, procs: list[psutil.Process]) -> None:
        with self.lock:
            self.procs = procs
            for p in self._tree():
                try:
                    p.cpu_percent(None)
                except psutil.Error:
                    pass
            self.job = {"job": name, "t0": time.time(), "ram": 0.0, "vram": 0.0, "cpu_sum": 0.0, "cpu_peak": 0.0,
                        "gpu_util": 0.0, "n": 0}

    def stop(self) -> dict:
        with self.lock:
            j, self.job = self.job, None
        j["secs"] = time.time() - j.pop("t0")
        j["cpu_avg"] = j.pop("cpu_sum") / max(1, j.pop("n"))
        j.pop("recent", None)
        self.rows.append(j)
        print(row(j, self.gpu.ok), flush=True)
        return j

    def _tree(self) -> list[psutil.Process]:
        out = []
        for p in self.procs:
            try:
                for q in [p] + p.children(recursive=True):
                    out.append(self.known.setdefault(q.pid, q))
            except psutil.Error:
                pass
        return out

    def _run(self) -> None:
        while True:
            time.sleep(0.25)
            with self.lock:
                j = self.job
                if j is None:
                    continue
                ram = cpu = 0.0
                for p in self._tree():
                    try:
                        ram += p.memory_info().rss
                        cpu += p.cpu_percent(None)
                    except psutil.Error:
                        pass
                # Windows counts CPU time in 15.6 ms steps per thread, so one 0.25 s
                # sample of a many-threaded process can read several times too high:
                # peaks are taken over the last second.
                cores = cpu / 100.0
                recent = j.setdefault("recent", [])
                recent.append(cores)
                del recent[:-4]
                j["ram"] = max(j["ram"], ram / 2**30)
                j["vram"] = max(j["vram"], (self.gpu.mem_mb - self.gpu_base) / 1024)
                j["gpu_util"] = max(j["gpu_util"], self.gpu.util)
                j["cpu_sum"] += cores
                j["cpu_peak"] = max(j["cpu_peak"], sum(recent) / len(recent))
                j["n"] += 1


class EngineProc:
    def __init__(self, env: dict) -> None:
        python = sys.executable
        self.p = subprocess.Popen(
            [python, "-u", os.path.join(HERE, "engine.py")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={**os.environ, "PYTHONIOENCODING": "utf-8", **env}, text=True, encoding="utf-8",
        )
        self.next = 1
        self.events: list[dict] = []
        self.replies: dict[int, dict] = {}
        self.cv = threading.Condition()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self) -> None:
        for line in self.p.stdout:
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            with self.cv:
                if "id" in msg and "event" not in msg:
                    self.replies[msg["id"]] = msg
                else:
                    self.events.append(msg)
                self.cv.notify_all()

    def send(self, msg: dict) -> None:
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()

    def request(self, cmd: str, on_event=None, **args) -> dict:
        rid, self.next = self.next, self.next + 1
        self.send({"id": rid, "cmd": cmd, **args})
        seen = 0
        with self.cv:
            while rid not in self.replies:
                self.cv.wait(0.2)
                if on_event:
                    for ev in self.events[seen:]:
                        if ev.get("id") == rid:
                            on_event(ev)
                    seen = len(self.events)
        r = self.replies.pop(rid)
        if not r.get("ok"):
            raise RuntimeError(r.get("error"))
        return r["result"]


def read_pcm(path: str, seconds: float | None = None) -> bytes:
    with wave.open(path, "rb") as w:
        n = w.getnframes() if seconds is None else min(w.getnframes(), int(seconds * w.getframerate()))
        return w.readframes(n)


HEADER = f"{'Job':34} {'Time':>7} {'RAM peak':>9} {'GPU mem':>8} {'GPU use':>8} {'CPU avg':>11} {'CPU peak':>11}"


def row(r: dict, gpu_ok: bool) -> str:
    g = f"{r['vram']:.2f} GB" if gpu_ok else "n/a"
    u = f"{r['gpu_util']:.0f}%" if gpu_ok else "n/a"
    return (f"{r['job']:34} {r['secs']:6.1f}s {r['ram']:6.2f} GB {g:>8} {u:>8} "
            f"{r['cpu_avg']:5.1f} cores {r['cpu_peak']:5.1f} cores")


def ensure_ollama(url: str, env: dict) -> None:
    """Start `ollama serve` like the app does (restarting it so `env` applies)."""
    for p in ollama_procs():
        try:
            p.kill()
        except psutil.Error:
            pass
    time.sleep(2)
    flags = 0x08000000 if sys.platform == "win32" else 0
    subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=flags,
                     env={**os.environ, **env})
    for _ in range(60):
        time.sleep(0.5)
        try:
            urllib.request.urlopen(f"{url}/api/tags", timeout=3).read()
            return
        except Exception:  # noqa: BLE001
            pass
    raise RuntimeError("Ollama didn't start")


def ollama_procs() -> list[psutil.Process]:
    out = []
    for p in psutil.process_iter(["name"]):
        if "ollama" in (p.info["name"] or "").lower():
            out.append(p)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mic")
    ap.add_argument("system")
    ap.add_argument("--device", default=None, help="auto | cuda | cpu (default: the app's setting)")
    ap.add_argument("--dictation-s", type=float, default=30.0)
    ap.add_argument("--skip-llm", action="store_true")
    ap.add_argument("--llm-only", action="store_true", help="only the task AI step, on the longest saved meeting")
    ap.add_argument("--profile", choices=["before", "after"], default="after",
                    help="the task AI request as the app sent it before/after the memory changes")
    a = ap.parse_args()

    s = app_settings()
    device = a.device or s.get("whisper_device", "auto")
    langs = s.get("languages") or [s.get("language") or "en"]
    translate = {"all": True, "gujarati": ["gu"]}.get(s.get("translate", "gujarati"), False)
    common = {"model": s.get("whisper_model", "auto"), "device": device, "languages": langs,
              "translate": translate, "prefer": s.get("prefer_indic", "gu"), "hf_token": s.get("hf_token") or None}
    print(f"device={device} languages={langs} cores={psutil.cpu_count()} ram={psutil.virtual_memory().total / 2**30:.1f} GB")
    print(HEADER, flush=True)

    gpu = Gpu()
    meter = Meter(gpu)
    if a.llm_only:
        row_ = sqlite3.connect(DB).execute(
            "SELECT transcript FROM meetings WHERE kind = 'meeting' AND transcript IS NOT NULL "
            "ORDER BY length(transcript) DESC LIMIT 1"
        ).fetchone()
        bench_llm(a, s, device, json.loads(row_[0]), gpu, meter)
        if gpu.ok:
            gpu.proc.kill()
        return
    eng = EngineProc({})
    me = psutil.Process(eng.p.pid)

    meter.start("Load speech model", [me])
    info = eng.request("load", **common)
    meter.stop()
    print(f"  (speech model: {info['model']} on {info['device']})", flush=True)

    meter.start("Idle, model loaded", [me])
    time.sleep(5)
    meter.stop()

    meter.start("Live dictation", [me])
    eng.request("stream_start", sid=1, silence_ms=700, **common)
    pcm = read_pcm(a.mic, a.dictation_s)
    step = 3200  # 100 ms of 16-bit 16 kHz
    t = time.time()
    for i in range(0, len(pcm), step):
        eng.send({"cmd": "audio", "sid": 1, "pcm": base64.b64encode(pcm[i : i + step]).decode()})
        t += 0.1
        time.sleep(max(0.0, t - time.time()))
    eng.request("stream_stop", sid=1)
    meter.stop()

    stage = {"name": None}

    def on_event(ev: dict) -> None:
        st = ev.get("stage") or ""
        name = "Meeting: speaker detection" if "speaker" in st.lower() else "Meeting: transcription"
        if ev.get("event") == "progress" and name != stage["name"] and "ready" not in st.lower():
            if stage["name"]:
                meter.stop()
            meter.start(name, [me])
            stage["name"] = name

    res = eng.request("meeting", on_event=on_event, mic_path=a.mic, system_path=a.system, **common)
    if stage["name"]:
        meter.stop()
    segments = res["segments"]
    eng.p.kill()
    time.sleep(2)

    if not a.skip_llm:
        bench_llm(a, s, device, segments, gpu, meter)
    if gpu.ok:
        gpu.proc.kill()


# The app's answer format and (shortened) instructions, from llm.rs.
SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "tasks": {"type": "array", "items": {
            "type": "object",
            "properties": {"description": {"type": "string"}, "assigned_by": {"type": ["string", "null"]},
                           "due": {"type": ["string", "null"]}, "quote": {"type": ["string", "null"]}},
            "required": ["description", "assigned_by", "due", "quote"],
        }},
    },
    "required": ["summary", "tasks"],
}
SYSTEM = ("You are an assistant that reads meeting transcripts and extracts the action items that belong to ONE "
          "specific person (the user). The conversation may mix English, Hindi and Gujarati; always write the "
          "summary and tasks in English. Return a one-sentence summary and the user's tasks.")


def context_for(prompt: str) -> int:
    """Same as `context_for` in llm.rs."""
    ascii_n = sum(c.isascii() for c in prompt)
    need = ascii_n * 2 // 7 + (len(prompt) - ascii_n) + 1536
    return min(8192, max(2048, -(-need // 1024) * 1024))


def bench_llm(a, s: dict, device: str, segments: list[dict], gpu: Gpu, meter: Meter) -> None:
    transcript = "\n".join(f"{x['speaker']}: {x['text']}" for x in segments)
    user = (f"The user is {s.get('user_name') or 'the user'}.\nTranscript:\n\"\"\"\n{transcript}\n\"\"\"\n\n"
            "Extract the user's action items and summarize.")
    model = s.get("llm_model", "qwen3:4b")
    url = (s.get("ollama_url") or "http://127.0.0.1:11434").rstrip("/")
    if a.profile == "before":
        opts, env = {"temperature": 0.1, "num_ctx": 8192}, {}
    else:
        opts = {"temperature": 0.1, "num_ctx": context_for(SYSTEM + user), "num_predict": 1536,
                "num_thread": max(2, psutil.cpu_count(logical=False) // 2)}
        env = {"OLLAMA_FLASH_ATTENTION": "1", "OLLAMA_KV_CACHE_TYPE": "q8_0"}
    if device == "cpu":
        opts["num_gpu"] = 0
    print(f"  (task AI, {a.profile}: {opts})", flush=True)
    ensure_ollama(url, env)
    time.sleep(2)
    body = {"model": model, "stream": False, "think": False, "keep_alive": 0, "format": SCHEMA, "options": opts,
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]}
    meter.gpu_base = gpu.mem_mb
    meter.start(f"Finding tasks ({model})", ollama_procs())
    req = urllib.request.Request(f"{url}/api/chat", json.dumps(body).encode(), {"Content-Type": "application/json"})

    def refresh() -> None:  # the model runner starts after the request
        while meter.job:
            time.sleep(0.5)
            with meter.lock:
                meter.procs = ollama_procs()

    threading.Thread(target=refresh, daemon=True).start()
    try:
        out = json.loads(urllib.request.urlopen(req, timeout=900).read())
        tasks = json.loads(out["message"]["content"]).get("tasks", [])
        print(f"  ({len(tasks)} tasks, {out.get('eval_count')} tokens written)", flush=True)
    except Exception as e:  # noqa: BLE001
        print(f"  task AI failed: {e}")
    meter.stop()


if __name__ == "__main__":
    main()
