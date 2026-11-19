"""Main loop with a custom wake-word model: wake by the model, Whisper only after it."""
import sys

from test_wake_pipeline import _run, _silence_frames, _speech_frames

from conftest import ears

wake = sys.modules["gera_wake"]


class _Detector:
    """Hears «Гера» on the given frame number."""

    name = "тест"

    def __init__(self, hit_on: int):
        self.frames = 0
        self.hit_on = hit_on

    def feed(self, frame):
        self.frames += 1
        return self.frames == self.hit_on

    def reset(self):
        pass


def _plugin(monkeypatch, detector):
    detail = "своя модель: тест" if detector else "Whisper"
    monkeypatch.setattr(wake, "load_wake_plugin", lambda environ=None: (detector, detail))


def test_custom_model_wakes_and_the_command_is_sent(monkeypatch, capsys):
    _plugin(monkeypatch, _Detector(hit_on=8))
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert kinds.count("wake") == 1
    assert next(e for e in events if e["type"] == "wake").get("via") == "keyword"
    assert [e["text"] for e in events if e["type"] == "command"] == ["какая погода"]
    engines = next(e for e in events if e["type"] == "engines")
    assert engines["keyword"] is True
    assert engines["wake"] == "своя модель: тест"


def test_without_a_model_hit_whisper_does_not_wake(monkeypatch, capsys):
    _plugin(monkeypatch, _Detector(hit_on=10_000))
    frames = _speech_frames(40) + _silence_frames(40)

    events = _run(monkeypatch, capsys, frames, "Гера, какая погода")
    kinds = [event["type"] for event in events]

    assert "wake" not in kinds
    assert "command" not in kinds


def test_push_to_talk_mode_ignores_the_wake_word(monkeypatch, capsys):
    _plugin(monkeypatch, _Detector(hit_on=8))

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


def test_engines_report_whisper_and_the_speech_detector(monkeypatch, capsys):
    _plugin(monkeypatch, None)

    events = _run(monkeypatch, capsys, _silence_frames(5), "")
    engines = next(e for e in events if e["type"] == "engines")

    assert engines["keyword"] is False
    assert engines["wake"] == "Whisper"
    assert engines["speech"] in ("silero", "spectral")
