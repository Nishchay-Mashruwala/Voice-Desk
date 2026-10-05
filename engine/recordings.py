"""Recordings on disk: FLAC (lossless, ~half the size of WAV) via PyAV, which
faster-whisper already brings along - no extra download.

The app records WAV (simple and crash-safe while recording); once a recording
has been processed it is compressed here. Everything that reads audio accepts
both.
"""

from __future__ import annotations

import os

import numpy as np

from runtime import SAMPLE_RATE, log, read_wav

CHUNK = SAMPLE_RATE * 10  # samples per encoded frame batch (10 s, keeps memory flat)


def read_audio(path: str) -> np.ndarray:
    """16 kHz mono float32 from a WAV or FLAC recording."""
    if path.lower().endswith(".wav"):
        return read_wav(path)
    pcm = []
    import av

    with av.open(path) as f:
        for frame in f.decode(audio=0):
            pcm.append(frame.to_ndarray().reshape(-1))
    if not pcm:
        return np.zeros(0, np.float32)
    a = np.concatenate(pcm)
    return a.astype(np.float32) / 32768.0 if a.dtype == np.int16 else a.astype(np.float32)


def write_flac(path: str, pcm16: np.ndarray) -> None:
    """Write 16 kHz mono int16 samples as FLAC (via a temp file, so a crash never leaves half a file)."""
    import av

    tmp = path + ".part"
    with av.open(tmp, "w", format="flac") as out:
        stream = out.add_stream("flac", rate=SAMPLE_RATE, layout="mono")
        stream.format = "s16"
        for i in range(0, len(pcm16), CHUNK):
            frame = av.AudioFrame.from_ndarray(np.ascontiguousarray(pcm16[i : i + CHUNK]).reshape(1, -1), format="s16", layout="mono")
            frame.sample_rate = SAMPLE_RATE
            for packet in stream.encode(frame):
                out.mux(packet)
        for packet in stream.encode(None):
            out.mux(packet)
    os.replace(tmp, path)


def compress(wav_path: str) -> str:
    """WAV -> FLAC next to it; the WAV is deleted only once the FLAC decodes to
    exactly the same samples. Returns the FLAC's path."""
    import wave

    flac = os.path.splitext(wav_path)[0] + ".flac"
    with wave.open(wav_path, "rb") as w:
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    write_flac(flac, pcm)
    back = np.round(read_audio(flac) * 32768.0).astype(np.int32)
    if len(back) != len(pcm) or not np.array_equal(back, pcm.astype(np.int32)):
        os.remove(flac)
        raise RuntimeError(f"FLAC check failed for {wav_path}; kept the WAV")
    before, after = os.path.getsize(wav_path), os.path.getsize(flac)
    os.remove(wav_path)
    log(f"compressed {os.path.basename(wav_path)}: {before / 1e6:.1f} -> {after / 1e6:.1f} MB")
    return flac


def mix(paths: list[str], out_path: str) -> str:
    """Mix tracks (a meeting's mic + computer audio) into one FLAC, as long as the longest."""
    tracks = [read_audio(p) for p in paths if os.path.exists(p)]
    n = max((len(t) for t in tracks), default=0)
    total = np.zeros(n, np.float32)
    for t in tracks:
        total[: len(t)] += t
    write_flac(out_path, (np.clip(total, -1, 1) * 32767).astype(np.int16))
    return out_path


def cmd_compress(req: dict) -> dict:
    """{"paths": [wav, ...]} -> {"done": {wav: flac}, "failed": {wav: error}}"""
    done, failed = {}, {}
    for p in req.get("paths") or []:
        try:
            if p.lower().endswith(".wav") and os.path.exists(p):
                done[p] = compress(p)
        except Exception as e:  # noqa: BLE001
            failed[p] = str(e)
            log(f"compress {p}: {e}")
    return {"done": done, "failed": failed}


def cmd_mix(req: dict) -> dict:
    return {"path": mix(req["paths"], req["out"])}
