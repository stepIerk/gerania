# -*- coding: utf-8 -*-
"""
Is this 30 ms frame human speech? Two detectors behind one `prob(frame)`.

* `SileroSpeechDetector` — Silero VAD v5 (ONNX, MIT). A small neural network
  trained to tell speech from noise, music, typing and fans; the best open
  VAD. Needs `onnxruntime` and the model file (`scripts/setup_voice.sh`
  downloads both).
* `SpectralSpeechDetector` — numpy only: energy in the voice band, spectral
  flatness and pitch periodicity. Rejects clicks, knocks, hiss and fans; weaker
  on music and TV, where Silero helps.

The ears ask `create_speech_detector()` once and fall back to the spectral one
when Silero is unavailable; the reason goes to the `engines` event.
"""
import os

import numpy as np

from gera_wake import Chunker

SAMPLE_RATE = 16000
DEFAULT_SILERO_MODEL = os.path.expanduser(
    "~/Library/Application Support/Gerania/models/silero_vad.onnx"
)

# Spectral detector: what a voiced speech frame looks like.
BAND_LOW, BAND_HIGH = 300.0, 3400.0
BAND_RATIO_MIN = 0.045      # share of the energy in the voice band
FLATNESS_MAX = 0.55         # voice has a comb-like spectrum, noise a flat one
PERIODICITY_MIN = 0.30      # normalised autocorrelation peak at the pitch lag
PITCH_MIN_HZ, PITCH_MAX_HZ = 70.0, 400.0
SILENT_RMS = 1e-4


class SpectralSpeechDetector:
    """Speech probability from three cues: pitch (0.5), comb spectrum (0.3), voice band (0.2)."""

    name = "spectral"

    def __init__(self, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self._lag_min = int(sample_rate / PITCH_MAX_HZ)
        self._lag_max = int(sample_rate / PITCH_MIN_HZ)

    def prob(self, frame: np.ndarray) -> float:
        frame = frame.astype(np.float64)
        if float(np.sqrt(np.mean(frame * frame))) < SILENT_RMS:
            return 0.0
        spectrum = np.abs(np.fft.rfft(frame * np.hanning(frame.size))) ** 2
        freqs = np.fft.rfftfreq(frame.size, 1.0 / self.sample_rate)
        band = (freqs >= BAND_LOW) & (freqs <= BAND_HIGH)
        total = spectrum[freqs >= 60].sum() + 1e-12
        ratio = spectrum[band].sum() / total
        in_band = spectrum[band] + 1e-12
        flatness = float(np.exp(np.log(in_band).mean()) / in_band.mean())
        # Pitch is the strongest cue (fans, hiss and clicks have none), so it
        # carries half of the score: without it a frame never reaches 0.6.
        score = 0.5 if self.periodicity(frame) > PERIODICITY_MIN else 0.0
        score += 0.3 if flatness < FLATNESS_MAX else 0.0
        score += 0.2 if ratio > BAND_RATIO_MIN else 0.0
        return score

    def periodicity(self, frame: np.ndarray) -> float:
        """Peak of the normalised autocorrelation in the pitch range (0…1)."""
        centred = frame - frame.mean()
        energy = float(np.dot(centred, centred))
        if energy <= 1e-12:
            return 0.0
        lag_max = min(self._lag_max, centred.size - 1)
        if lag_max <= self._lag_min:
            return 0.0
        correlation = np.correlate(centred, centred, mode="full")[centred.size - 1:]
        return float(np.max(correlation[self._lag_min: lag_max + 1]) / energy)

    def reset(self) -> None:
        pass


class SileroSpeechDetector:
    """Silero VAD v5 through onnxruntime: 512-sample chunks with 64 samples of context."""

    name = "silero"
    CHUNK = 512
    CONTEXT = 64

    def __init__(self, session):
        self._session = session
        self._chunker = Chunker(self.CHUNK)
        self._last = 0.0
        self.reset()

    @classmethod
    def load(cls, model_path: str):
        import onnxruntime  # noqa: PLC0415 — optional dependency

        options = onnxruntime.SessionOptions()
        options.inter_op_num_threads = 1
        options.intra_op_num_threads = 1
        session = onnxruntime.InferenceSession(
            model_path, sess_options=options, providers=["CPUExecutionProvider"]
        )
        return cls(session)

    def prob(self, frame: np.ndarray) -> float:
        for block in self._chunker.feed(frame):
            chunk = np.concatenate([self._context, block.astype(np.float32)])[np.newaxis, :]
            output, state = self._session.run(
                None,
                {"input": chunk, "state": self._state, "sr": np.array(SAMPLE_RATE, dtype=np.int64)},
            )
            self._state = state
            self._context = chunk[0, -self.CONTEXT:]
            self._last = float(np.asarray(output).reshape(-1)[0])
        return self._last

    def reset(self) -> None:
        self._state = np.zeros((2, 1, 128), dtype=np.float32)
        self._context = np.zeros(self.CONTEXT, dtype=np.float32)
        self._chunker.reset()
        self._last = 0.0


def create_speech_detector(environ=os.environ, loader=None):
    """`(detector, detail)`: Silero when possible, the spectral detector otherwise."""
    if environ.get("GERA_VAD", "").strip().lower() == "spectral":
        return SpectralSpeechDetector(), "спектр (выбран в настройках)"
    path = environ.get("GERA_SILERO_MODEL", "").strip() or DEFAULT_SILERO_MODEL
    if not os.path.isfile(path):
        return SpectralSpeechDetector(), "спектр (нет модели Silero — запустите setup_voice.sh)"
    try:
        detector = (loader or SileroSpeechDetector.load)(path)
        # One silent frame: a broken model fails here, not in the middle of a phrase.
        detector.prob(np.zeros(480, dtype=np.float32))
        detector.reset()
    except ImportError:
        return SpectralSpeechDetector(), "спектр (не установлен onnxruntime)"
    except Exception as error:  # noqa: BLE001 — any model error falls back
        return SpectralSpeechDetector(), f"спектр (Silero не запустился: {error})"
    return detector, "Silero VAD"


def speech_ratio(probs, threshold: float) -> float:
    """Share of frames above `threshold`; 0 for an empty list."""
    probs = list(probs)
    if not probs:
        return 0.0
    return sum(1 for value in probs if value >= threshold) / len(probs)
