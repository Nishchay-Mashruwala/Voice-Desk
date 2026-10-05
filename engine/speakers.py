"""Who spoke when ("speaker diarization"), with small ONNX models via sherpa-onnx.

pyannote's segmentation model (6 MB) finds where up to 3 people talk in each
10 s window; a 3D-Speaker ERes2Net voice model (40 MB) tells people apart; the
windows are clustered into speakers. Runs in the engine process on the CPU.

Measured against pyannote/PyTorch (which this replaced) on two real calls:
97-98% agreement on who spoke when, ~10 s instead of ~90 s for a 70 s call,
and ~0.1 GB of RAM instead of ~3 GB. No Hugging Face token needed.
"""

from __future__ import annotations

import os
import tarfile
import threading
import urllib.request

import numpy as np

from runtime import SAMPLE_RATE, THREADS, Download, log, models_dir

_RELEASES = "https://github.com/k2-fsa/sherpa-onnx/releases/download"
SEGMENTATION_URL = f"{_RELEASES}/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2"
EMBEDDING_URL = f"{_RELEASES}/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx"
SEGMENTATION_FILE = "speakers-segmentation-3.0.onnx"
EMBEDDING_FILE = "speakers-eres2net.onnx"

# Cosine-distance threshold for joining voices into one speaker. Tuned on two
# real calls: 0.7 split one person in two, 1.0 merged two people.
CLUSTER_THRESHOLD = 0.8
# Voice match for "remember this voice": the same person scored 0.43-0.93 and
# different people at most 0.18 (cosine, two real calls, ERes2Net).
SAME_PERSON = 0.35
# Only name speakers with at least this much speech (short clips match poorly).
MIN_NAMED_S = 3.0

# Speakers with less speech than this in the whole recording are one person's
# voice briefly sounding different: they join the speaker talking next to them.
MIN_SPEAKER_S = 1.5

_lock = threading.Lock()
_diarizer = None
_extractor = None


# Seconds to wait for the server to answer or send more: without a limit a
# stalled connection could hang a meeting forever (this runs holding `_lock`).
TIMEOUT_S = 30


def _download(url: str, dest: str) -> None:
    tmp = dest + ".part"
    log(f"downloading {url}")
    with urllib.request.urlopen(url, timeout=TIMEOUT_S) as resp, open(tmp, "wb") as out:
        size = int(resp.headers.get("Content-Length") or 0) or None
        report = Download("Speaker detection model", size)
        while chunk := resp.read(1 << 20):
            out.write(chunk)
            report.add(len(chunk))
    if size is not None and os.path.getsize(tmp) != size:
        raise OSError(f"download of {url} was cut off")
    report.finish()
    if url.endswith(".tar.bz2"):
        with tarfile.open(tmp, "r:bz2") as tar:
            member = next(m for m in tar.getmembers() if m.name.endswith("/model.onnx"))
            with tar.extractfile(member) as src, open(dest + ".x", "wb") as out:
                out.write(src.read())
        os.remove(tmp)
        tmp = dest + ".x"
    os.replace(tmp, dest)


def model_paths() -> tuple[str, str]:
    """The two model files, downloaded (once) if missing."""
    d = models_dir()
    seg, emb = os.path.join(d, SEGMENTATION_FILE), os.path.join(d, EMBEDDING_FILE)
    for url, path in ((SEGMENTATION_URL, seg), (EMBEDDING_URL, emb)):
        if not os.path.exists(path):
            _download(url, path)
    return seg, emb


def _get():
    global _diarizer
    with _lock:
        if _diarizer is None:
            import sherpa_onnx

            seg, emb = model_paths()
            config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
                segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
                    pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(model=seg),
                    num_threads=THREADS,
                ),
                embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=emb, num_threads=THREADS),
                clustering=sherpa_onnx.FastClusteringConfig(num_clusters=-1, threshold=CLUSTER_THRESHOLD),
                min_duration_on=0.3,
                min_duration_off=0.5,
            )
            if not config.validate():
                raise RuntimeError("speaker detection models are invalid")
            _diarizer = sherpa_onnx.OfflineSpeakerDiarization(config)
        return _diarizer


def unload() -> None:
    global _diarizer, _extractor
    with _lock:
        _diarizer = None
        _extractor = None


def voice_of(audio: np.ndarray) -> np.ndarray:
    """A person's voice as a unit vector (up to 30 s of their speech is used)."""
    global _extractor
    with _lock:
        if _extractor is None:
            import sherpa_onnx

            _, emb = model_paths()
            _extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
                sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=emb, num_threads=THREADS)
            )
        stream = _extractor.create_stream()
        stream.accept_waveform(SAMPLE_RATE, np.ascontiguousarray(audio[: 30 * SAMPLE_RATE], dtype=np.float32))
        stream.input_finished()
        v = np.asarray(_extractor.compute(stream), dtype=np.float32)
    return v / (np.linalg.norm(v) or 1.0)


def speaker_audio(audio: np.ndarray, spans) -> np.ndarray:
    """One speaker's speech: their (start_s, end_s) spans joined."""
    clips = [audio[int(a * SAMPLE_RATE) : int(b * SAMPLE_RATE)] for a, b in spans]
    return np.concatenate(clips) if clips else np.zeros(0, np.float32)


def match_people(voices: dict[str, np.ndarray], people: list[dict]) -> dict[str, str]:
    """Speaker label -> remembered name, for voices close enough to a person
    (best matches first; each person names at most one speaker)."""
    if not people:
        return {}
    known = [(p["name"], np.asarray(p["embedding"], dtype=np.float32)) for p in people]
    pairs = sorted(
        ((float(v @ (e / (np.linalg.norm(e) or 1.0))), label, name) for label, v in voices.items() for name, e in known),
        reverse=True,
    )
    out: dict[str, str] = {}
    for score, label, name in pairs:
        if score >= SAME_PERSON and label not in out and name not in out.values():
            out[label] = name
    return out


def name_speakers(audio: np.ndarray, turns, people: list[dict]) -> list[tuple[float, float, str]]:
    """Replace speaker labels with remembered names where the voice matches."""
    if not people:
        return turns
    spans: dict[str, list] = {}
    for a, b, spk in turns:
        spans.setdefault(spk, []).append((a, b))
    voices = {
        spk: voice_of(speaker_audio(audio, s))
        for spk, s in spans.items()
        if sum(b - a for a, b in s) >= MIN_NAMED_S
    }
    names = match_people(voices, people)
    if names:
        log(f"recognised: {names}")
    return [(a, b, names.get(spk, spk)) for a, b, spk in turns]


def fold_tiny(turns: list[tuple[float, float, str]], min_s: float = MIN_SPEAKER_S) -> list[tuple[float, float, str]]:
    """Give the turns of speakers with < min_s of speech to the nearest real speaker."""
    total: dict[str, float] = {}
    for a, b, spk in turns:
        total[spk] = total.get(spk, 0.0) + b - a
    real = [t for t in turns if total[t[2]] >= min_s]
    if not real:
        return turns
    out = []
    for a, b, spk in turns:
        if total[spk] < min_s:
            spk = min(real, key=lambda t: min(abs(a - t[1]), abs(t[0] - b)))[2]
        out.append((a, b, spk))
    return out


def diarize(audio: np.ndarray) -> list[tuple[float, float, str]]:
    """[(start_s, end_s, "SPEAKER_00"), ...] for 16 kHz mono float32 audio."""
    result = _get().process(np.ascontiguousarray(audio, dtype=np.float32)).sort_by_start_time()
    turns = [(round(r.start, 3), round(r.end, 3), f"SPEAKER_{r.speaker:02d}") for r in result]
    return fold_tiny(turns)
