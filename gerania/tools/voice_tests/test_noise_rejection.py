"""Noise must not wake Gera: frame-level speech detection and Whisper's word confidence."""
import sys

import numpy as np
import pytest
from test_wake_pipeline import _run, _silence_frames, _speech_frames

from conftest import ears

vad_module = sys.modules["gera_vad"]

RATE = 16000
T = np.arange(480) / RATE


def _voice(pitch=140.0, level=0.03):
    """Voiced speech-like frame: a pitch with harmonics up to ~3 kHz."""
    return sum(level / k * np.sin(2 * np.pi * pitch * k * T) for k in range(1, 20)).astype(np.float32)


def _white(level=0.05, seed=0):
    return np.random.default_rng(seed).normal(0, level, 480).astype(np.float32)


def _click():
    frame = np.zeros(480, dtype=np.float32)
    frame[10] = 0.9
    return frame


# --- spectral detector -------------------------------------------------------------

def test_spectral_detector_tells_voice_from_noise():
    detector = vad_module.SpectralSpeechDetector()
    threshold = ears.SPEECH_PROB_MIN["spectral"]

    assert detector.prob(_voice()) >= threshold
    assert detector.prob(_voice(pitch=220)) >= threshold
    assert detector.prob(_white()) < threshold
    assert detector.prob(_click()) < threshold
    assert detector.prob(np.zeros(480, dtype=np.float32)) == 0.0


# --- Silero wrapper with a fake ONNX session -----------------------------------------

class _FakeSession:
    def __init__(self, probability):
        self.calls = []
        self.probability = probability

    def run(self, outputs, feeds):
        self.calls.append({name: np.array(value) for name, value in feeds.items()})
        return np.array([[self.probability]], dtype=np.float32), feeds["state"] + 1


def test_silero_gets_512_samples_with_64_of_context_and_keeps_state():
    session = _FakeSession(0.9)
    detector = vad_module.SileroSpeechDetector(session)

    first = detector.prob(np.ones(480, dtype=np.float32))
    second = detector.prob(np.ones(480, dtype=np.float32))

    assert first == 0.0                 # 480 < 512: no chunk yet
    assert second == pytest.approx(0.9)
    call = session.calls[0]
    assert call["input"].shape == (1, 576)
    assert call["state"].shape == (2, 1, 128)
    assert int(call["sr"]) == 16000
    detector.prob(np.ones(480, dtype=np.float32))
    detector.prob(np.ones(480, dtype=np.float32))
    assert float(session.calls[1]["state"][0, 0, 0]) == 1.0     # state carried over


def test_detector_choice_falls_back_to_spectral(tmp_path):
    detector, detail = vad_module.create_speech_detector({"GERA_SILERO_MODEL": str(tmp_path / "x.onnx")})
    assert detector.name == "spectral"
    assert "Silero" in detail

    model = tmp_path / "silero.onnx"
    model.write_bytes(b"x")

    def broken(path):
        raise RuntimeError("bad model")

    detector, detail = vad_module.create_speech_detector({"GERA_SILERO_MODEL": str(model)}, loader=broken)
    assert detector.name == "spectral"
    assert "bad model" in detail

    detector, detail = vad_module.create_speech_detector(
        {"GERA_SILERO_MODEL": str(model)},
        loader=lambda path: vad_module.SileroSpeechDetector(_FakeSession(0.1)),
    )
    assert detector.name == "silero"
    assert detail == "Silero VAD"


# --- VAD with the detector ---------------------------------------------------------

def test_loud_noise_does_not_start_a_phrase_but_voice_does():
    vad = ears.VAD(speech=vad_module.SpectralSpeechDetector())
    for seed in range(40):
        vad.feed(_white(0.08, seed))
    assert not vad.active

    for _ in range(5):
        vad.feed(_voice(level=0.2))
    assert vad.active


def test_steady_loud_noise_lifts_the_noise_floor():
    vad = ears.VAD(speech=vad_module.SpectralSpeechDetector())
    before = vad.noise
    for seed in range(200):
        vad.feed(_white(0.05, seed))
    assert vad.noise > before


def test_phrase_of_mostly_noise_is_filtered():
    vad = ears.VAD(speech=vad_module.SpectralSpeechDetector())
    result = None
    frames = [_voice(level=0.2)] * 3 + [_white(0.08, seed) for seed in range(60)] + [np.zeros(480, np.float32)] * 40
    for frame in frames:
        result = vad.feed(frame) or result
    # Speech ended the moment the noise began: the phrase is short, never 60 frames of "speech".
    assert result is not None
    assert result[0] == "filtered" or len(result[1]) < 60 * 480


# --- Whisper's confidence in «Гера» ---------------------------------------------------

def test_wake_confident_uses_the_word_probability():
    sure = ears.Transcript("Гера, какая погода", [(" Гера,", 0.92), (" какая", 0.9), (" погода", 0.95)])
    noise = ears.Transcript("Гера.", [(" Гера.", 0.12)])
    loose = ears.Transcript("Гиро", [(" Гиро", 0.5)])

    assert ears.wake_confident(sure)
    assert not ears.wake_confident(noise)
    assert not ears.wake_confident(loose)        # loose forms need more
    assert ears.wake_confident("Гера")           # plain text: nothing to check


def test_hallucinated_wake_on_noise_does_not_wake_gera(monkeypatch, capsys):
    unsure = ears.Transcript("Гера, какая погода", [(" Гера,", 0.1), (" какая", 0.3), (" погода", 0.3)])
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, unsure)
    kinds = [event["type"] for event in events]

    assert "wake" not in kinds
    assert "command" not in kinds


def test_confident_wake_still_works(monkeypatch, capsys):
    sure = ears.Transcript("Гера, какая погода", [(" Гера,", 0.9), (" какая", 0.9), (" погода", 0.9)])
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, sure)

    assert "wake" in [event["type"] for event in events]
    assert [e["text"] for e in events if e["type"] == "command"] == ["какая погода"]


def test_noise_never_reaches_whisper(monkeypatch, capsys):
    # Even if Whisper "heard" the wake word, loud noise never becomes a phrase.
    frames = [_white(0.08, seed) for seed in range(60)] + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert "utterance_start" not in kinds
    assert "wake" not in kinds


def test_config_tunes_noise_rejection():
    before = (ears.WAKE_MIN_PROB, dict(ears.SPEECH_PROB_MIN))
    try:
        ears.apply_config({"values": {"wake_min_prob": 0.7, "speech_prob_silero": 0.65}})
        assert ears.WAKE_MIN_PROB == 0.7
        assert ears.SPEECH_PROB_MIN["silero"] == 0.65
    finally:
        ears.WAKE_MIN_PROB = before[0]
        ears.SPEECH_PROB_MIN.clear()
        ears.SPEECH_PROB_MIN.update(before[1])

