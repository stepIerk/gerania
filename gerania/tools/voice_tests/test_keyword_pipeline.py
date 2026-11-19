"""Main loop with Porcupine and Eagle: wake by the detector, Whisper only after it."""
import sys

import numpy as np
from test_wake_pipeline import _run, _silence_frames, _speech_frames

from conftest import ears

wake = sys.modules["gera_wake"]


class _Detector:
    """Hears «Гера» on the given frame number."""

    def __init__(self, hit_on: int):
        self.frames = 0
        self.hit_on = hit_on

    def feed(self, frame):
        self.frames += 1
        return self.frames == self.hit_on

    def reset(self):
        pass


class _Verifier:
    def __init__(self, score: float):
        self.gate = wake.OwnerGate(0.5)
        self._score = score

    def feed(self, frame):
        pass

    def is_owner(self):
        return self._score >= 0.5

    def score(self):
        return self._score


def _engines(monkeypatch, detector=None, verifier=None):
    monkeypatch.setattr(wake.KeywordDetector, "create",
                        classmethod(lambda cls, environ=None: (detector, "test")))
    monkeypatch.setattr(wake.OwnerVerifier, "create",
                        classmethod(lambda cls, environ=None: (verifier, "test")))


def test_porcupine_wakes_and_the_command_is_sent(monkeypatch, capsys):
    _engines(monkeypatch, detector=_Detector(hit_on=8))
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert kinds.count("wake") == 1
    assert next(e for e in events if e["type"] == "wake").get("via") == "keyword"
    commands = [event for event in events if event["type"] == "command"]
    assert [command["text"] for command in commands] == ["какая погода"]
    engines = next(e for e in events if e["type"] == "engines")
    assert engines["keyword"] is True


def test_without_porcupine_hit_whisper_does_not_wake_or_run(monkeypatch, capsys):
    _engines(monkeypatch, detector=_Detector(hit_on=10_000))
    calls = []
    frames = _speech_frames(40) + _silence_frames(40)

    original = ears.transcribe

    def counting(audio, prompt=None, model=None):
        calls.append(model)
        return original(audio, prompt, model)

    monkeypatch.setattr(ears, "transcribe", counting)
    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert "wake" not in kinds
    assert "command" not in kinds


def test_foreign_voice_cannot_wake_gera(monkeypatch, capsys):
    _engines(monkeypatch, detector=_Detector(hit_on=8), verifier=_Verifier(score=0.1))
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert "wake_rejected" in kinds
    assert "wake" not in kinds
    assert "command" not in kinds


def test_owner_voice_wakes_gera(monkeypatch, capsys):
    _engines(monkeypatch, detector=_Detector(hit_on=8), verifier=_Verifier(score=0.9))
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")

    assert [e["text"] for e in events if e["type"] == "command"] == ["какая погода"]
    assert next(e for e in events if e["type"] == "engines")["owner"] is True


def test_push_to_talk_mode_ignores_the_wake_word(monkeypatch, capsys):
    _engines(monkeypatch, detector=_Detector(hit_on=8))

    class PttIPC(ears.IPC):
        def __init__(self):
            super().__init__()
            self.listen_mode = wake.LISTEN_PUSH_TO_TALK

    monkeypatch.setattr(ears, "IPC", PttIPC)
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert "wake" not in kinds
    assert "utterance_start" not in kinds
    assert "command" not in kinds
