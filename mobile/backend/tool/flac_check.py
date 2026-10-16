"""PC check of the app's FLAC files against libsndfile (Python `soundfile`).

python flac_check.py <file.flac> <file.wav>: reads both, says whether every
sample is the same, and how big the FLAC is next to the WAV.
"""
import os
import sys

import numpy as np
import soundfile as sf

flac, wav = sys.argv[1], sys.argv[2]
a, ra = sf.read(flac, dtype="int16")
b, rb = sf.read(wav, dtype="int16")
same = ra == rb and a.shape == b.shape and np.array_equal(a, b)
print(f"{'identical' if same else 'DIFFERENT'}: {len(a)} samples at {ra} Hz; "
      f"FLAC {os.path.getsize(flac) / os.path.getsize(wav):.0%} of the WAV")
sys.exit(0 if same else 1)
