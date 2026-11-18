"""Мягкий mute и малая модель: фраза не рвётся, фолбэк работает."""
import numpy as np
from conftest import ears


def _loud_frame() -> np.ndarray:
    return np.full(ears.FRAME, 0.2, dtype=np.float32)


def _start_utterance(vad) -> None:
    for _ in range(ears.START_FRAMES):
        vad.feed(_loud_frame())
    assert vad.active is True


def test_skip_keeps_the_phrase_alive():
    """Наш собственный звук посреди фразы не сбрасывает VAD."""
    vad = ears.VAD()
    _start_utterance(vad)
    before = vad.duration()

    vad.skip(np.zeros(ears.FRAME, dtype=np.float32))

    assert vad.active is True
    assert vad.duration() > before
    assert vad.trailing_silence() == 0


def test_skip_ignores_frames_while_not_listening():
    vad = ears.VAD()

    vad.skip(np.zeros(ears.FRAME, dtype=np.float32))

    assert vad.active is False


def test_a_stuck_mute_does_not_stretch_the_phrase_forever():
    vad = ears.VAD()
    _start_utterance(vad)

    for _ in range(ears.MAX_SKIP_FRAMES + 1):
        vad.skip(np.zeros(ears.FRAME, dtype=np.float32))

    assert vad.active is False


def test_partial_model_falls_back_to_the_big_one(monkeypatch):
    """`transcribe()` возвращает sentinel вместо исключения — фолбэк обязан сработать."""
    worker = ears.WhisperWorker(model="small", fallback="big")
    monkeypatch.setattr(ears, "transcribe", lambda *args, **kwargs: ("", 1.0, -9.0))
    worker._audio = np.zeros(ears.FRAME, dtype=np.float32)
    worker._token = 7

    worker._run()

    assert worker.model == "big"
    result = worker.take()
    assert result is not None
    assert result[4] == 7
