# -*- coding: utf-8 -*-
"""
Listen modes and a pluggable wake word for the GERANIA ears.

By default «Гера» is found by Whisper in the recognised text (see
`find_wake` and `wake_confident` in gera_ears.py). A dedicated detector can be
plugged in without touching the ears: `GERA_WAKE_PLUGIN=/path/to/module.py`
names a Python module with

    def create(environ) -> detector

where `detector.feed(frame) -> bool` gets every 30 ms frame (float32, 16 kHz,
mono) and returns True on the frame where the wake word ended, and
`detector.reset()` forgets the buffered audio. An openWakeWord model fits this
shape in a dozen lines. With a plugin, Whisper runs only after the wake word
and for stop words while Gera works.
"""
import importlib.util
import os

import numpy as np

LISTEN_ALWAYS = "always"
LISTEN_NOT_WHILE_ANSWERING = "not_while_answering"
LISTEN_PUSH_TO_TALK = "push_to_talk"
LISTEN_MODES = (LISTEN_ALWAYS, LISTEN_NOT_WHILE_ANSWERING, LISTEN_PUSH_TO_TALK)


def to_int16(frame: np.ndarray) -> np.ndarray:
    """Float32 [-1, 1] samples of sounddevice → int16 PCM (what most KWS engines take)."""
    clipped = np.clip(frame, -1.0, 1.0)
    return (clipped * 32767.0).astype(np.int16)


class Chunker:
    """Collects 30 ms frames into the block size an engine wants."""

    def __init__(self, size: int, dtype=np.float32):
        self.size = max(1, int(size))
        self.dtype = dtype
        self._buffer = np.zeros(0, dtype=dtype)

    def feed(self, samples: np.ndarray):
        self._buffer = np.concatenate([self._buffer, samples.astype(self.dtype)])
        while self._buffer.size >= self.size:
            block = self._buffer[: self.size]
            self._buffer = self._buffer[self.size:]
            yield block

    def reset(self) -> None:
        self._buffer = np.zeros(0, dtype=self.dtype)


def frame_is_heard(mode: str, busy: bool, speaking: bool, awaiting: bool) -> bool:
    """Whether the ears listen to the microphone at all right now.

    * `always` — always (wake word, stop words during the answer);
    * `not_while_answering` — not while Gera works or speaks; stop by hotkey;
    * `push_to_talk` — only after the hotkey (the app sends `arm`).
    """
    if mode == LISTEN_PUSH_TO_TALK:
        return awaiting
    if mode == LISTEN_NOT_WHILE_ANSWERING and (busy or speaking):
        return awaiting
    return True


def wake_allowed(mode: str, speaking: bool) -> bool:
    """Whether a detected wake word may wake Gera.

    While Gera speaks the microphone hears her own voice, so a wake word then
    is ignored; stopping her goes through stop words or the hotkey.
    """
    if mode == LISTEN_PUSH_TO_TALK:
        return False
    return not speaking


def load_wake_plugin(environ=os.environ):
    """`(detector or None, reason)` from `GERA_WAKE_PLUGIN`; Whisper when absent."""
    path = environ.get("GERA_WAKE_PLUGIN", "").strip()
    if not path:
        return None, "Whisper"
    if not os.path.isfile(path):
        return None, f"Whisper (нет файла модели {os.path.basename(path)})"
    try:
        spec = importlib.util.spec_from_file_location("gera_wake_plugin", path)
        if spec is None or spec.loader is None:
            return None, "Whisper (модуль не загружается)"
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        detector = module.create(environ)
        if not (callable(getattr(detector, "feed", None)) and callable(getattr(detector, "reset", None))):
            return None, "Whisper (у модели нет feed/reset)"
    except Exception as error:  # noqa: BLE001 — a broken plugin must not stop the ears
        return None, f"Whisper (своя модель упала: {error})"
    name = getattr(detector, "name", None) or os.path.basename(path)
    return detector, f"своя модель: {name}"
