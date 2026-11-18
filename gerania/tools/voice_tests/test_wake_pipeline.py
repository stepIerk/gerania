"""Сквозная проверка реплики: Гера просыпается на ходу и команду отправляет не дожидаясь конца.

Тест гоняет настоящий VAD и главный цикл `gera_ears.py` на синтетическом звуке:
подменяются только микрофон, очередь кадров и Whisper.
"""
import json
import time
import types

import numpy as np
import pytest
from conftest import ears

PHRASE = "Гера, какая погода"


def _speech_frames(count: int) -> list:
    """Тон 1 кГц: проходит и порог громкости, и спектральный фильтр."""
    time = np.arange(ears.FRAME) / ears.SAMPLE_RATE
    tone = (0.05 * np.sin(2 * np.pi * 1000 * time)).astype(np.float32)
    return [tone.copy() for _ in range(count)]


def _silence_frames(count: int) -> list:
    return [np.zeros(ears.FRAME, dtype=np.float32) for _ in range(count)]


class _FakeQueue:
    def __init__(self, items):
        self.items = list(items)

    def get(self, timeout=None):
        if not self.items:
            raise KeyboardInterrupt
        return self.items.pop(0)

    def put(self, item):
        self.items.append(item)


class _FakeStream:
    frames: list = []

    def __init__(self, *args, **kwargs):
        self.callback = kwargs.get("callback")

    def start(self):
        for frame in self.frames:
            self.callback(frame.reshape(-1, 1), len(frame), None, None)

    def stop(self):
        pass

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _run(monkeypatch, capsys, frames, text, partial_text=None):
    """Прогоняет главный цикл и возвращает список событий.

    `partial_text` — что «слышит» малая модель на ходу, `text` — что разбирает
    большая в конце. По умолчанию обе модели слышат одно и то же.
    """
    queue = _FakeQueue([])
    monkeypatch.setattr(
        ears,
        "queue",
        types.SimpleNamespace(Queue=lambda: queue, Empty=type("Empty", (Exception,), {})),
    )
    monkeypatch.setattr(_FakeStream, "frames", frames)
    monkeypatch.setattr(ears.sd, "InputStream", _FakeStream)
    monkeypatch.setattr(ears.IPC, "start_reader", lambda self: None)

    def fake_transcribe(audio, prompt=None, model=None):
        return (partial_text or text, 0.05, -0.2) if model else (text, 0.05, -0.2)

    monkeypatch.setattr(ears, "transcribe", fake_transcribe)
    monkeypatch.setattr(ears, "IPC_MODE", True)
    ears.main()
    out = capsys.readouterr().out
    return [json.loads(line) for line in out.splitlines() if line.startswith("{")]


@pytest.mark.parametrize("text", [PHRASE])
def test_wake_and_command_come_before_the_utterance_ends(monkeypatch, capsys, text):
    # Малая модель на ходу слышит только «Гера», большую команду разбирает пауза.
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, text, partial_text="Гера")

    kinds = [event["type"] for event in events]
    assert "wake" in kinds
    assert "command" in kinds

    wake_at = kinds.index("wake")
    command_at = kinds.index("command")
    end_at = kinds.index("utterance_end")
    # Гера проснулась и команда ушла, пока реплика ещё не закончилась.
    assert wake_at < command_at < end_at

    commands = [event for event in events if event["type"] == "command"]
    assert len(commands) == 1
    assert commands[0]["text"] == "какая погода"
    assert commands[0]["via"] == "partial"


def test_partial_text_is_reported_while_speaking(monkeypatch, capsys):
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, PHRASE)
    kinds = [event["type"] for event in events]
    assert "partial" in kinds
    partial = next(event for event in events if event["type"] == "partial")
    assert partial["text"] == "какая погода"


def test_without_the_wake_word_nothing_is_sent(monkeypatch, capsys):
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, "просто фраза без призыва")
    kinds = [event["type"] for event in events]
    assert "wake" not in kinds
    assert "command" not in kinds


def test_push_to_talk_sends_the_command_without_the_wake_word(monkeypatch, capsys):
    """Push-to-talk: команда уходит сразу, без ожидания конца реплики."""
    monkeypatch.setattr(ears.State, "awaiting", True)
    monkeypatch.setattr(ears.State, "await_deadline", time.time() + 30)
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, "какая погода")
    kinds = [event["type"] for event in events]
    assert "command" in kinds
    command = next(event for event in events if event["type"] == "command")
    assert command["text"] == "какая погода"
    # Ожидание снято вместе с командой — таймаута быть не должно.
    assert "await_timeout" not in kinds


def test_wake_and_stop_is_not_sent_to_the_agent(monkeypatch, capsys):
    """«Гера, стоп» — остановка, а не промпт: раньше она уходила как команда."""
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, "Гера, стоп")
    kinds = [event["type"] for event in events]

    assert "stop" in kinds
    assert "command" not in kinds
    # Стоп-событие одно: частичный и финальный разбор не дублируют его.
    assert kinds.count("stop") == 1


def test_stop_word_while_busy_does_not_need_the_wake_word(monkeypatch, capsys):
    """Пока агент работает, голое «стоп» обязано срабатывать."""

    class BusyIPC(ears.IPC):
        def __init__(self):
            super().__init__()
            self.busy = True

    monkeypatch.setattr(ears, "IPC", BusyIPC)
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, "стоп")
    kinds = [event["type"] for event in events]

    assert "stop" in kinds
    assert "command" not in kinds
    stop = next(event for event in events if event["type"] == "stop")
    assert stop["scope"] == "busy"


def test_final_text_without_the_wake_word_still_becomes_the_command(monkeypatch, capsys):
    """Малая модель поймала «Гера», большая потеряла его в финальном тексте.

    Раньше финальный текст молча выбрасывался, и в live уходил только огрызок,
    услышанный на ходу.
    """
    monkeypatch.setattr(ears, "COMMAND_PAUSE_SEC", 10.0)
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(
        monkeypatch,
        capsys,
        frames,
        "Открой Safari и найди погоду",
        partial_text="Гера, открой",
    )
    commands = [event for event in events if event["type"] == "command"]

    assert commands[-1]["text"] == "Открой Safari и найди погоду"
    assert commands[-1]["via"] == "final"
    utterance_end = next(i for i, event in enumerate(events) if event["type"] == "utterance_end")
    assert events.index(commands[-1]) < utterance_end


def test_a_cut_off_final_text_does_not_replace_the_full_command(monkeypatch, capsys):
    """Большая модель обрезала начало — остаётся уже накопленная полная фраза."""
    monkeypatch.setattr(ears, "COMMAND_PAUSE_SEC", 10.0)
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(
        monkeypatch,
        capsys,
        frames,
        "и найди погоду",
        partial_text="Гера, открой Safari и найди погоду",
    )
    commands = [event for event in events if event["type"] == "command"]

    assert commands[-1]["text"] == "открой Safari и найди погоду"


def test_a_cut_off_final_text_with_the_wake_word_does_not_shorten_the_command(monkeypatch, capsys):
    """Финальный текст с «Гера» тоже не должен обрезать уже накопленное."""
    monkeypatch.setattr(ears, "COMMAND_PAUSE_SEC", 10.0)
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(
        monkeypatch,
        capsys,
        frames,
        "Гера, открой Safari",
        partial_text="Гера, открой Safari и найди погоду",
    )
    commands = [event for event in events if event["type"] == "command"]

    assert commands[-1]["text"] == "открой Safari и найди погоду"
    assert all(event["text"] != "открой Safari" for event in commands[1:])


def test_stop_without_the_wake_word_after_a_partial_wake(monkeypatch, capsys):
    """«Гера, стоп» остаётся стопом, даже если финальный текст без «Гера»."""
    monkeypatch.setattr(ears, "COMMAND_PAUSE_SEC", 10.0)
    frames = _speech_frames(40) + _silence_frames(40)
    events = _run(monkeypatch, capsys, frames, "стоп", partial_text="Гера")
    kinds = [event["type"] for event in events]

    assert kinds.count("stop") == 1
    assert "command" not in kinds
    stop = next(event for event in events if event["type"] == "stop")
    assert stop["scope"] == "explicit"
