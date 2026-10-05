"""Voice Desk speech engine.

Long-running sidecar spawned by the Tauri backend. Speaks JSON Lines:

  stdin  <- {"id": 1, "cmd": "meeting", ...}            request (gets exactly one reply)
            {"cmd": "audio", "sid": 1, "pcm": "<b64>"}   live microphone audio (no reply)
  stdout -> {"id": 1, "ok": true, "result": {...}}       reply
            {"id": 1, "event": "progress", ...}          progress for a request
            {"event": "utterance", "sid": 1, ...}        live dictation result
            {"event": "download", "what": ..., "done_mb": ..., "total_mb": ...}
                                                         a model being downloaded

Only protocol messages go to stdout; all logging goes to stderr.

Memory: Whisper lives on the GPU when there is one; voice ID (26 MB) and
speaker detection (46 MB, see speakers.py) are small ONNX models on the CPU.
PyTorch is only loaded for Hindi/Gujarati. Idle models are unloaded after a
configurable time.

  python engine.py --prefetch   downloads models ahead of time (used by setup)
"""

from __future__ import annotations

import runtime  # noqa: F401  (first: thread limits, CUDA DLLs)

try:
    # Use the computer's certificate store for HTTPS: antivirus that scans HTTPS
    # (and company proxies) re-sign downloads with their own root certificate,
    # which Python's bundled list doesn't know, so model downloads failed there.
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

import json
import os
import sys
import threading
import time
import traceback
from typing import Callable

import numpy as np

import indic
import speakers
from meeting import cmd_meeting, cmd_speaker_voice
from recordings import cmd_compress, cmd_mix, read_audio
from runtime import SAMPLE_RATE, isolate_protocol_pipes, log, send
from speech import speech_only
from stream import cmd_stream_start, cmd_stream_stop, cmd_stream_update, on_audio, streams
from transcriber import Transcriber, transcriber, whisper_files, whisper_need
from voice import voiceprint
from voiceprint import VoicePrint

# --------------------------------------------------------------------------- #
# Other commands
# --------------------------------------------------------------------------- #


def cmd_models_in_use(req: dict) -> dict:
    """Which downloaded models the current settings use (Settings -> Storage
    won't offer to delete these): the Whisper sizes this PC would pick, and
    whether Hindi/Gujarati needs IndicConformer."""
    langs, translate = req.get("languages"), req.get("translate") or False
    need = whisper_need(langs, translate)
    names = {c[0] for c in Transcriber._candidates(req.get("model", "auto"), req.get("device", "auto"), need)}
    if transcriber.active_model != "none":
        names.add(transcriber.active_model)
    return {"whisper": sorted(names), "indic": indic.wanted(langs, translate)}


def cmd_load(req: dict) -> dict:
    transcriber.load(req.get("model", "auto"), req.get("device", "auto"), req.get("languages"), req.get("translate") or False)
    return {"device": transcriber.active_device, "model": transcriber.active_model}


def cmd_enroll(req: dict) -> dict:
    """Build the user's voice profile from a recording of them reading aloud."""
    audio = speech_only(read_audio(req["path"]))
    seconds = len(audio) / SAMPLE_RATE
    if seconds < 6:
        raise ValueError(f"Only {seconds:.0f}s of speech was heard. Please read the text aloud for about 15 seconds.")
    win, hop = 3 * SAMPLE_RATE, int(1.5 * SAMPLE_RATE)
    embs = [voiceprint.embed(audio[i : i + win]) for i in range(0, len(audio) - win + 1, hop)]
    profile = np.mean(embs, axis=0)
    profile /= np.linalg.norm(profile)
    consistency = float(np.mean([VoicePrint.similarity(profile, e) for e in embs]))
    np.save(req["out"], profile)
    return {"seconds": round(seconds, 1), "consistency": round(consistency, 2)}


def cmd_configure(req: dict) -> dict:
    global idle_unload_s
    idle_unload_s = max(0, int(req.get("unload_after_min", 10))) * 60
    return {}


COMMANDS: dict[str, Callable[[dict], dict]] = {
    "load": cmd_load,
    "configure": cmd_configure,
    "stream_start": cmd_stream_start,
    "stream_update": cmd_stream_update,
    "stream_stop": cmd_stream_stop,
    "meeting": cmd_meeting,
    "speaker_voice": cmd_speaker_voice,
    "compress": cmd_compress,
    "mix": cmd_mix,
    "models_in_use": cmd_models_in_use,
    "enroll": cmd_enroll,
}

idle_unload_s = 10 * 60
# Requests running now, and when the last one ended. A meeting's speaker
# detection or a long transcription doesn't touch Whisper for minutes; the
# process used to exit in the middle of one.
busy = 0
last_done = time.time()
busy_lock = threading.Lock()


def gpu_keepalive() -> None:
    """While listening, give the GPU a tiny job (16 ms) every second.

    Laptop GPUs drop to power-saving clocks after a few idle seconds and ramp
    up slowly; measured here, a phrase after a 6 s pause took 3.7-5.3 s instead
    of 1.5 s. The keepalive costs ~1.6% of the GPU and keeps it at 1.8 s.
    """
    import ctranslate2

    tiny = None
    while True:
        time.sleep(1.0)
        model = transcriber.model
        if not streams or model is None or transcriber.active_device != "cuda":
            continue
        try:
            if tiny is None:
                mels = model.model.n_mels  # 128 for large-v3, 80 for older models
                tiny = ctranslate2.StorageView.from_array(np.zeros((1, mels, 100), np.float32))
            model.model.encode(tiny, to_cpu=False)
        except Exception as e:  # noqa: BLE001 — never let this break dictation
            log(f"gpu keepalive: {e}")
            tiny = None


def idle_watchdog() -> None:
    """Free all memory when Voice Desk hasn't been used for a while.

    Unloading the model alone keeps ~750 MB of CUDA libraries mapped, so the
    whole process exits instead; the app restarts it on the next request.
    """
    while True:
        time.sleep(30)
        with busy_lock:  # no request can start while deciding
            if idle_too_long(time.time()):
                log("idle: exiting to free memory")
                send({"event": "sleeping"})
                os._exit(0)


def idle_too_long(now: float) -> bool:
    if not idle_unload_s or not transcriber.loaded or streams or busy:
        return False
    return now - max(transcriber.last_used, last_done) > idle_unload_s


def handle(req: dict) -> None:
    global busy, last_done
    rid = req.get("id")
    with busy_lock:
        busy += 1
    try:
        fn = COMMANDS.get(req.get("cmd", ""))
        if fn is None:
            raise ValueError(f"unknown command: {req.get('cmd')}")
        send({"id": rid, "ok": True, "result": fn(req)})
    except Exception as e:  # noqa: BLE001
        log(traceback.format_exc())
        send({"id": rid, "ok": False, "error": str(e)})
    finally:
        with busy_lock:
            busy -= 1
            last_done = time.time()


def prefetch() -> None:
    """Download models ahead of time so the first run starts instantly."""
    import voiceprint as vp

    from transcriber import cpu_model, cuda_usable

    # Only what this computer will use: a GPU model only with the NVIDIA pack.
    names = ["large-v3-turbo", "small"] if cuda_usable() else [cpu_model()]
    for name in names:
        print(f"Downloading speech model '{name}'...", flush=True)
        whisper_files(name)
    print("Downloading voice-ID model...", flush=True)
    vp.model_file()
    print("Downloading speaker-detection models...", flush=True)
    speakers.model_paths()
    print("Checking the speech model loads...", flush=True)
    transcriber.load()
    print(f"OK: '{transcriber.active_model}' runs on {transcriber.active_device}.", flush=True)


def main() -> None:
    if "--prefetch" in sys.argv:
        prefetch()
        return
    isolate_protocol_pipes()
    threading.Thread(target=idle_watchdog, daemon=True).start()
    threading.Thread(target=gpu_keepalive, daemon=True).start()
    log("ready")
    send({"event": "ready"})
    # Each request runs on its own thread so dictation never waits behind a long
    # meeting job. Live audio chunks are handled inline to keep their order.
    for line in runtime.proto_in():
        # One malformed message (not JSON, missing "pcm", bad base64...) is
        # skipped; it must not end the engine and every dictation with it.
        try:
            line = line.strip()
            if not line:
                continue
            req = json.loads(line)
            if not isinstance(req, dict):
                raise ValueError("not a JSON object")
            if req.get("cmd") == "audio":
                on_audio(req)
                continue
            threading.Thread(target=handle, args=(req,), daemon=True).start()
        except Exception as e:  # noqa: BLE001
            log(f"bad message ignored ({e!r}): {line[:100]!r}")
    # stdin closed: the app exited.
    os._exit(0)


if __name__ == "__main__":
    main()
