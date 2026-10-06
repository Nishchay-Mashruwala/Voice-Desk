"""Shared plumbing for the engine: CPU thread limits and CUDA DLLs (set up
before numpy loads), the JSON-lines protocol, WAV files and model downloads.
Import first."""

from __future__ import annotations

import json
import os
import sys
import threading
import time
import wave
from typing import Any


def _worker_threads() -> int:
    """CPU threads for heavy work: half the physical cores, at least 2.

    Measured on an 8-core laptop: with every library using all cores, live
    dictation of Gujarati peaked at 14.6 of 16 threads and transcription at 14.9,
    making the whole computer stutter. Voice Desk runs on many kinds of laptops,
    so this follows the machine instead of a fixed number."""
    try:
        import psutil

        cores = psutil.cpu_count(logical=False)
    except Exception:  # noqa: BLE001
        cores = None
    cores = cores or max(1, (os.cpu_count() or 4) // 2)
    return max(2, cores // 2)


# Before numpy/onnxruntime load: they size their thread pools from these.
THREADS = int(os.environ.get("VOICEDESK_THREADS") or _worker_threads())
for _var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
    os.environ.setdefault(_var, str(THREADS))

import numpy as np  # noqa: E402  (after the thread limits above)

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")


def _add_cuda_dll_dirs() -> None:
    """Make pip-installed CUDA libs (nvidia-cublas-cu12, nvidia-cudnn-cu12) loadable.

    Only relevant on Windows/Linux with an NVIDIA GPU; macOS has no CUDA and
    Whisper simply runs on the CPU there.
    """
    import site

    for base in site.getsitepackages():
        nvidia = os.path.join(base, "nvidia")
        if not os.path.isdir(nvidia):
            continue
        for pkg in os.listdir(nvidia):
            if os.name == "nt":
                bin_dir = os.path.join(nvidia, pkg, "bin")
                if os.path.isdir(bin_dir):
                    os.add_dll_directory(bin_dir)
                    os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
            else:
                # Linux ignores LD_LIBRARY_PATH changes after startup, so preload the libs.
                import ctypes
                import glob

                for lib in sorted(glob.glob(os.path.join(nvidia, pkg, "lib", "*.so*"))):
                    try:
                        ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
                    except OSError:
                        pass


_add_cuda_dll_dirs()

SAMPLE_RATE = 16000
_out_lock = threading.Lock()

# Protocol streams. `main()` swaps these for private copies of the original pipes.
_proto_in = sys.stdin
_proto_out = sys.stdout


def log(*args: Any) -> None:
    print("[engine]", *args, file=sys.stderr, flush=True)


def send(msg: dict) -> None:
    line = json.dumps(msg, ensure_ascii=False)
    with _out_lock:
        _proto_out.write(line + "\n")
        _proto_out.flush()


def read_wav(path: str) -> np.ndarray:
    """Read a 16 kHz mono 16-bit WAV (what the Rust recorder writes) as float32."""
    with wave.open(path, "rb") as w:
        if w.getframerate() != SAMPLE_RATE or w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError(
                f"{path}: expected 16kHz mono s16, got {w.getframerate()}Hz "
                f"{w.getnchannels()}ch {w.getsampwidth() * 8}bit"
            )
        frames = w.readframes(w.getnframes())
    return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0


def isolate_protocol_pipes() -> None:
    """Keep the JSON protocol on private copies of the original stdin/stdout.

    - Libraries that print() would otherwise corrupt the protocol, so fd 1 is
      pointed at stderr.
    - On Windows, a thread that touches the stdin handle (GetFileType, spawning a
      subprocess, ...) while the main thread is blocked reading it deadlocks.
      fd 0 is pointed at the null device instead.
    """
    global _proto_in, _proto_out
    _proto_in = os.fdopen(os.dup(0), "r", encoding="utf-8", newline="\n")
    _proto_out = os.fdopen(os.dup(1), "w", encoding="utf-8", newline="\n")
    devnull = os.open(os.devnull, os.O_RDONLY)
    os.dup2(devnull, 0)
    os.close(devnull)
    os.dup2(2, 1)
    sys.stdin = open(os.devnull, encoding="utf-8")
    sys.stdout = sys.stderr


def proto_in():
    """The protocol input (a private copy of stdin once `isolate_protocol_pipes` ran)."""
    return _proto_in


def models_dir() -> str:
    """Where Voice Desk keeps the models it downloads itself (speaker detection...).
    Whisper models stay in the Hugging Face cache."""
    if os.name == "nt":
        base = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"), "VoiceDesk")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Caches/VoiceDesk")
    else:
        base = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "voicedesk")
    path = os.path.join(base, "models")
    os.makedirs(path, exist_ok=True)
    return path


# --------------------------------------------------------------------------- #
# Model downloads, with progress for the app
# --------------------------------------------------------------------------- #


class Download:
    """Progress of one model download, sent to the app as
    {"event": "download", "what", "done_mb", "total_mb"}: at most two a second,
    and a last one with done_mb == total_mb. Nothing is sent when nothing had
    to be downloaded (already cached)."""

    EVERY_S = 0.5

    def __init__(self, what: str, total_bytes: int | None = None) -> None:
        self.what = what
        self.total = total_bytes  # None: the sum of the progress bars' totals
        self.done = 0
        self.bars: list = []
        self.sent = 0.0
        self._lock = threading.Lock()

    def add(self, n: int) -> None:
        with self._lock:
            self.done += n
            now = time.time()
            if now - self.sent < self.EVERY_S:
                return
            self.sent = now
        self._send(self.done, self._total())

    def finish(self) -> None:
        if self.done or self.sent:
            total = self._total() or self.done
            self._send(total, total)

    def _total(self) -> int | None:
        if self.total is not None:
            return self.total
        return sum(b.total or 0 for b in self.bars) or None

    def _send(self, done: int, total: int | None) -> None:
        mb = 1024 * 1024
        send({"event": "download", "what": self.what, "done_mb": round(done / mb, 1),
              "total_mb": round(total / mb, 1) if total else None})

    def tqdm_class(self):
        """A silent progress bar for huggingface_hub's `tqdm_class` that counts
        the bytes written. huggingface_hub also opens bars for the file count
        and (Xet downloads) the bytes transferred; only the written bytes count,
        so nothing is counted twice."""
        from tqdm import tqdm

        report = self

        class Bar(tqdm):
            def __init__(self, *args, **kwargs) -> None:
                kwargs.pop("name", None)
                kwargs["disable"] = True
                super().__init__(*args, **kwargs)
                desc = str(kwargs.get("desc") or "").lower()
                self.counted = kwargs.get("unit") == "B" and "downloading bytes" not in desc
                if self.counted:
                    report.bars.append(self)
                    if self.n:  # resuming a partial download
                        report.add(int(self.n))

            def update(self, n=1):
                if self.counted and n:
                    self.n += n
                    report.add(int(n))
                return True

        return Bar


def _bytes_missing(repo: str, token, allow_patterns) -> int | None:
    """Size of the files `snapshot_download` will fetch (not cached yet), so the
    app gets a fixed total: the bars' totals only grow as files start (the
    Hindi/Gujarati model is 366+ files). None if the Hub can't be asked."""
    try:
        from huggingface_hub import HfApi, try_to_load_from_cache
        from huggingface_hub.hf_api import RepoFile
        from huggingface_hub.utils import filter_repo_objects

        files = [f for f in HfApi().list_repo_tree(repo, recursive=True, token=token) if isinstance(f, RepoFile)]
        wanted = set(filter_repo_objects([f.path for f in files], allow_patterns=allow_patterns))
        return sum(f.size for f in files if f.path in wanted and not isinstance(try_to_load_from_cache(repo, f.path), str))
    except Exception as e:  # noqa: BLE001
        log(f"download size unknown: {e}")
        return None


def hub_snapshot(repo: str, what: str, token=None, allow_patterns: list[str] | None = None) -> str:
    """`huggingface_hub.snapshot_download` with download events."""
    from huggingface_hub import snapshot_download

    report = Download(what, _bytes_missing(repo, token, allow_patterns))
    path = snapshot_download(repo, token=token, allow_patterns=allow_patterns, tqdm_class=report.tqdm_class())
    report.finish()
    return path


def hub_file(repo: str, filename: str, what: str) -> str:
    """One file from Hugging Face: the cached copy, else downloaded with events."""
    from huggingface_hub import hf_hub_download, try_to_load_from_cache

    cached = try_to_load_from_cache(repo, filename)
    if isinstance(cached, str):
        return cached
    report = Download(what)
    path = hf_hub_download(repo, filename, tqdm_class=report.tqdm_class())
    report.finish()
    return path
