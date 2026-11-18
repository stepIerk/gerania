#!/usr/bin/env python3
"""Проверка быстрого wake на записи голоса.

Прогоняет `gera_ears.py` через настоящий Whisper, но вместо микрофона отдаёт
ему WAV-файл. Печатает события с отметками времени — видно, как быстро Гера
просыпается и как быстро уходит команда.

    say -v Milena -o /tmp/gera.aiff "Гера, какая погода в Москве"
    afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/gera.aiff /tmp/gera.wav
    ~/.wake_agent_env/bin/python tools/voice/check_wake.py /tmp/gera.wav
"""
import json
import sys
import threading
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Resources" / "Voice"))

import numpy as np  # noqa: E402
import sounddevice as sd  # noqa: E402

import gera_ears as ears  # noqa: E402


def read_frames(path: str) -> list:
    """Кадры по 30 мс из WAV-файла."""
    with wave.open(path, "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        raw = handle.readframes(handle.getnframes())
    if width != 2:
        raise SystemExit("Нужен 16-битный WAV")
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    if rate != ears.SAMPLE_RATE:
        step = rate / ears.SAMPLE_RATE
        indexes = (np.arange(0, len(samples), step)).astype(int)
        samples = samples[indexes]
    size = ears.FRAME
    frames = [samples[i: i + size] for i in range(0, len(samples) - size + 1, size)]
    # Микрофон всегда приносит и тишину — добавляем её, иначе реплика не закроется.
    frames += [np.zeros(size, dtype=np.float32)] * int(4.0 / ears.FRAME_SEC)
    return frames


class StoppableIPC(ears.IPC):
    """IPC, который умеет остановить главный цикл."""

    instance = None

    def __init__(self):
        super().__init__()
        StoppableIPC.instance = self

    def start_reader(self):
        return None


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    frames = read_frames(path)
    if not frames:
        print("Файл пуст")
        return 1

    print(f"Аудио: {len(frames) * ears.FRAME_SEC:.2f} с")

    def feeder(callback):
        def loop():
            for frame in frames:
                time.sleep(ears.FRAME_SEC)
                callback(frame.reshape(-1, 1), len(frame), None, None)
            time.sleep(0.5)
            if StoppableIPC.instance:
                StoppableIPC.instance.should_exit = True

        threading.Thread(target=loop, daemon=True).start()

    class FakeStream:
        def __init__(self, *args, **kwargs):
            self.callback = kwargs.get("callback")

        def __enter__(self):
            feeder(self.callback)
            return self

        def __exit__(self, *args):
            return False

    sd.InputStream = FakeStream
    ears.IPC = StoppableIPC
    ears.IPC_MODE = True

    start = time.monotonic()
    original_emit = ears.IPC.emit

    def emit(self, kind, **fields):
        stamp = time.monotonic() - start
        tail = " ".join(f"{k}={json.dumps(v, ensure_ascii=False)}" for k, v in fields.items())
        print(f"[{stamp:6.2f} с] {kind} {tail}".rstrip(), flush=True)
        original_emit(self, kind, **fields)

    ears.IPC.emit = emit
    ears.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
