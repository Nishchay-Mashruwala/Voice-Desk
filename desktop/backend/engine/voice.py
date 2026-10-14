"""Is it the user's voice? Voice-ID model and the saved voice profile."""

from __future__ import annotations

import os

import numpy as np

from runtime import SAMPLE_RATE
from speech import speech_only
from voiceprint import VoicePrint

voiceprint = VoicePrint()
VOICE_THRESHOLD = 0.30  # cosine similarity; the user's voice scores ~0.35-0.6, others < 0.2


def load_profile(path: str | None) -> np.ndarray | None:
    if path and os.path.exists(path):
        return np.load(path)
    return None


def voice_score(profile: np.ndarray, audio: np.ndarray) -> float | None:
    speech = speech_only(audio)
    if len(speech) < SAMPLE_RATE // 2:
        return None  # too little speech to judge
    return round(VoicePrint.similarity(profile, voiceprint.embed(speech)), 3)
