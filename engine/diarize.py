"""Speaker diarization, run as a short-lived subprocess by engine.py.

torch + pyannote take ~700 MB of RAM once imported and Python never gives it
back, so diarization runs in its own process that exits when done.

  python diarize.py <audio.wav> [num_speakers]
  env HF_TOKEN=hf_...
  stdout -> {"turns": [[start, end, "SPEAKER_00"], ...]}  or  {"error": "..."}
"""

from __future__ import annotations

import json
import os
import sys
import wave

MODEL = "pyannote/speaker-diarization-community-1"


def main() -> None:
    # Keep stdout clean for the JSON result; libraries log to stderr.
    out = sys.stdout
    sys.stdout = sys.stderr
    try:
        import numpy as np
        import torch
        from pyannote.audio import Pipeline

        path = sys.argv[1]
        num_speakers = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] != "0" else None
        with wave.open(path, "rb") as w:
            rate = w.getframerate()
            audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0

        pipeline = Pipeline.from_pretrained(MODEL, token=os.environ.get("HF_TOKEN") or None)
        if pipeline is None:
            raise RuntimeError(
                f"pyannote model unavailable. Accept the terms at https://huggingface.co/{MODEL} "
                "and add a Hugging Face token in Settings."
            )
        torch.set_num_threads(int(os.environ.get("OMP_NUM_THREADS") or 2))
        # Smaller batches: much lower peak memory for a little more time.
        for attr in ("segmentation_batch_size", "embedding_batch_size"):
            if hasattr(pipeline, attr):
                setattr(pipeline, attr, 8)
        # The Processor setting decides: CPU only, or a GPU (the engine also sets
        # CUDA_VISIBLE_DEVICES to the chosen NVIDIA GPU).
        on_cpu = os.environ.get("VOICEDESK_DEVICE") == "cpu"
        if on_cpu:
            pass
        elif torch.cuda.is_available():
            pipeline.to(torch.device("cuda"))
        elif torch.backends.mps.is_available():  # Apple Silicon GPU
            pipeline.to(torch.device("mps"))

        kwargs = {"num_speakers": num_speakers} if num_speakers else {}
        result = pipeline({"waveform": torch.from_numpy(audio).unsqueeze(0), "sample_rate": rate}, **kwargs)
        # pyannote 4.x returns DiarizeOutput; 3.x returns an Annotation.
        annotation = getattr(result, "exclusive_speaker_diarization", None) or getattr(
            result, "speaker_diarization", result
        )
        turns = [[round(t.start, 3), round(t.end, 3), spk] for t, _, spk in annotation.itertracks(yield_label=True)]
        out.write(json.dumps({"turns": turns}))
    except Exception as e:  # noqa: BLE001
        msg = str(e)
        if "401" in msg or "gated" in msg.lower() or "restricted" in msg.lower():
            msg = (
                "Speaker detection needs a Hugging Face token. Accept the terms at "
                f"https://huggingface.co/{MODEL} and paste a Read token in Settings."
            )
        out.write(json.dumps({"error": msg}))
    out.flush()


if __name__ == "__main__":
    main()
