# -*- coding: utf-8 -*-
"""
Wake word and owner voice for the GERANIA ears.

* `KeywordDetector` — Picovoice Porcupine: an always-on detector of «Гера».
  It hears the word in a few milliseconds and costs almost no CPU, so Whisper
  only runs after the wake word (and for stop words while Gera works).
* `OwnerVerifier` — Picovoice Eagle: compares the voice with the profile
  recorded in the app and tells whether the owner is speaking. Gera's own
  speech, the TV and other people get a low score.
* `enroll_owner` — records the owner profile (the app runs it as a separate
  process with `--enroll-voice`).

Both engines are optional: without the AccessKey, the files or the packages
the ears fall back to the Whisper wake word and to no speaker check. The
reasons are reported once in the `ready` event.

Settings come from the environment set by the app (never from argv, which is
visible in `ps`):
  GERA_PV_ACCESS_KEY, GERA_WAKE_KEYWORD (.ppn), GERA_WAKE_MODEL (.pv),
  GERA_WAKE_SENSITIVITY, GERA_OWNER_PROFILE, GERA_OWNER_THRESHOLD.

Eagle changed its Python API between major versions: v1/v2 return
`(percent, feedback)` from `enroll` and take the profiles in the recognizer,
v3 returns a number and takes the profiles in `process`. Both shapes are
supported below.
"""
import os
from collections import deque
from typing import Callable, Optional

import numpy as np

LISTEN_ALWAYS = "always"
LISTEN_NOT_WHILE_ANSWERING = "not_while_answering"
LISTEN_PUSH_TO_TALK = "push_to_talk"
LISTEN_MODES = (LISTEN_ALWAYS, LISTEN_NOT_WHILE_ANSWERING, LISTEN_PUSH_TO_TALK)

# Owner score over the last ~1.5 s: Eagle scores a short chunk, a phrase needs
# the best moment of it, not the average with the pauses.
OWNER_WINDOW_SEC = 1.5
DEFAULT_OWNER_THRESHOLD = 0.5
DEFAULT_SENSITIVITY = 0.6


def to_int16(frame: np.ndarray) -> np.ndarray:
    """Float32 [-1, 1] samples of sounddevice → int16 PCM of Picovoice."""
    clipped = np.clip(frame, -1.0, 1.0)
    return (clipped * 32767.0).astype(np.int16)


class Chunker:
    """Collects 30 ms frames into the block size an engine wants."""

    def __init__(self, size: int):
        self.size = max(1, int(size))
        self._buffer = np.zeros(0, dtype=np.int16)

    def feed(self, pcm: np.ndarray):
        self._buffer = np.concatenate([self._buffer, pcm.astype(np.int16)])
        while self._buffer.size >= self.size:
            block = self._buffer[: self.size]
            self._buffer = self._buffer[self.size:]
            yield block

    def reset(self) -> None:
        self._buffer = np.zeros(0, dtype=np.int16)


def frame_is_heard(mode: str, busy: bool, speaking: bool, awaiting: bool) -> bool:
    """Whether the ears listen to the microphone at all right now.

    * `always` — always (wake and barge-in during the answer);
    * `not_while_answering` — not while Gera works or speaks; stop by hotkey;
    * `push_to_talk` — only after the hotkey (the app sends `arm`).
    """
    if mode == LISTEN_PUSH_TO_TALK:
        return awaiting
    if mode == LISTEN_NOT_WHILE_ANSWERING and (busy or speaking):
        return awaiting
    return True


def wake_allowed(mode: str, speaking: bool, owner_gate: bool) -> bool:
    """Whether a detected wake word may wake Gera.

    While Gera speaks, the microphone hears her: without the owner check a wake
    word in her own speech would interrupt the answer, so barge-in by voice
    needs the owner gate.
    """
    if mode == LISTEN_PUSH_TO_TALK:
        return False
    if speaking:
        return mode == LISTEN_ALWAYS and owner_gate
    return True


class OwnerGate:
    """Hysteresis over the owner scores: one loud cough does not flip it."""

    def __init__(self, threshold: float = DEFAULT_OWNER_THRESHOLD, window: int = 8):
        self.threshold = threshold
        self.scores: "deque[float]" = deque(maxlen=window)

    def add(self, score: float) -> None:
        self.scores.append(float(score))

    def best(self) -> float:
        return max(self.scores) if self.scores else 0.0

    def is_owner(self) -> bool:
        return self.best() >= self.threshold

    def reset(self) -> None:
        self.scores.clear()


class SpeakerTracker:
    """Who is talking while the live dialog owns the microphone.

    Events: `owner` — the owner speaks (at once), `other` — someone else or
    Gera's own voice speaks for `other_after` seconds, `silence` — nobody for
    `silence_after` seconds. Only changes are returned, so the app gets a few
    events a minute instead of a stream.
    """

    def __init__(self, other_after: float = 0.4, silence_after: float = 0.8):
        self.other_after = other_after
        self.silence_after = silence_after
        self.current = "silence"
        self._other_since: Optional[float] = None
        self._quiet_since: Optional[float] = None

    def update(self, voiced: bool, owner: bool, now: float) -> Optional[str]:
        if voiced:
            self._quiet_since = None
            if owner:
                self._other_since = None
                return self._switch("owner")
            if self._other_since is None:
                self._other_since = now
            if now - self._other_since >= self.other_after:
                return self._switch("other")
            return None
        self._other_since = None
        if self._quiet_since is None:
            self._quiet_since = now
        if now - self._quiet_since >= self.silence_after:
            return self._switch("silence")
        return None

    def _switch(self, state: str) -> Optional[str]:
        if state == self.current:
            return None
        self.current = state
        return state

    def reset(self) -> None:
        self.current = "silence"
        self._other_since = None
        self._quiet_since = None


class KeywordDetector:
    """Porcupine wrapper. `create` returns `(detector or None, reason)`."""

    def __init__(self, engine):
        self._engine = engine
        self._chunker = Chunker(engine.frame_length)

    @classmethod
    def create(cls, environ=os.environ):
        key = environ.get("GERA_PV_ACCESS_KEY", "").strip()
        keyword = environ.get("GERA_WAKE_KEYWORD", "").strip()
        model = environ.get("GERA_WAKE_MODEL", "").strip()
        if not key:
            return None, "нет ключа Picovoice"
        if not keyword or not os.path.isfile(keyword):
            return None, "нет файла слова «Гера» (.ppn)"
        if model and not os.path.isfile(model):
            return None, "нет файла русской модели (.pv)"
        try:
            import pvporcupine  # noqa: PLC0415 — optional dependency
        except ImportError:
            return None, "не установлен pvporcupine"
        sensitivity = _float(environ.get("GERA_WAKE_SENSITIVITY"), DEFAULT_SENSITIVITY)
        try:
            engine = pvporcupine.create(
                access_key=key,
                keyword_paths=[keyword],
                model_path=model or None,
                sensitivities=[min(1.0, max(0.0, sensitivity))],
            )
        except Exception as error:  # noqa: BLE001 — any engine error disables it
            return None, f"Porcupine: {error}"
        return cls(engine), "Porcupine"

    def feed(self, frame: np.ndarray) -> bool:
        """True when the wake word ended inside this frame."""
        hit = False
        for block in self._chunker.feed(to_int16(frame)):
            if self._engine.process(block) >= 0:
                hit = True
        return hit

    def reset(self) -> None:
        self._chunker.reset()

    def close(self) -> None:
        try:
            self._engine.delete()
        except Exception:  # noqa: BLE001
            pass


class OwnerVerifier:
    """Eagle wrapper. `create` returns `(verifier or None, reason)`."""

    def __init__(self, engine, profile, profiles_in_process: bool, threshold: float):
        self._engine = engine
        self._profile = profile
        self._profiles_in_process = profiles_in_process
        size = getattr(engine, "min_process_samples", None) or getattr(engine, "frame_length", 512)
        self._chunker = Chunker(size)
        self.gate = OwnerGate(threshold)

    @classmethod
    def create(cls, environ=os.environ):
        key = environ.get("GERA_PV_ACCESS_KEY", "").strip()
        path = environ.get("GERA_OWNER_PROFILE", "").strip()
        if not key:
            return None, "нет ключа Picovoice"
        if not path or not os.path.isfile(path):
            return None, "голос владельца не записан"
        try:
            import pveagle  # noqa: PLC0415 — optional dependency
        except ImportError:
            return None, "не установлен pveagle"
        threshold = _float(environ.get("GERA_OWNER_THRESHOLD"), DEFAULT_OWNER_THRESHOLD)
        try:
            with open(path, "rb") as handle:
                profile = pveagle.EagleProfile.from_bytes(handle.read())
            try:
                engine = pveagle.create_recognizer(access_key=key, speaker_profiles=[profile])
                in_process = False
            except TypeError:
                engine = pveagle.create_recognizer(access_key=key)
                in_process = True
        except Exception as error:  # noqa: BLE001
            return None, f"Eagle: {error}"
        return cls(engine, profile, in_process, threshold), "Eagle"

    def feed(self, frame: np.ndarray) -> None:
        for block in self._chunker.feed(to_int16(frame)):
            if self._profiles_in_process:
                scores = self._engine.process(block, [self._profile])
            else:
                scores = self._engine.process(block)
            if scores is not None and len(scores) > 0:
                self.gate.add(float(scores[0]))

    def is_owner(self) -> bool:
        return self.gate.is_owner()

    def score(self) -> float:
        return self.gate.best()

    def reset(self) -> None:
        self._chunker.reset()
        self.gate.reset()
        try:
            self._engine.reset()
        except Exception:  # noqa: BLE001 — not every version has reset()
            pass


def enroll_percent(result) -> float:
    """`enroll` returns a number (v3) or `(percent, feedback)` (v1/v2)."""
    if isinstance(result, tuple):
        return float(result[0])
    return float(result)


def enroll_owner(
    out_path: str,
    read_frame: Callable[[], Optional[np.ndarray]],
    emit: Callable[..., None],
    environ=os.environ,
    profiler=None,
) -> bool:
    """Records the owner profile from `read_frame()` frames into `out_path`.

    `emit("enroll_progress", percent=...)` reports the progress; the result is
    `enroll_done` or `error`. `profiler` is injected by the tests.
    """
    if profiler is None:
        key = environ.get("GERA_PV_ACCESS_KEY", "").strip()
        if not key:
            emit("error", message="Нет ключа Picovoice: введите его в настройках голоса.")
            return False
        try:
            import pveagle  # noqa: PLC0415
            profiler = pveagle.create_profiler(access_key=key)
        except Exception as error:  # noqa: BLE001
            emit("error", message=f"Eagle не запустился: {error}")
            return False
    size = getattr(profiler, "frame_length", None) or getattr(profiler, "min_enroll_samples", 16000)
    chunker = Chunker(size)
    percent = 0.0
    last_sent = -1
    while percent < 100.0:
        frame = read_frame()
        if frame is None:
            emit("error", message="Запись голоса прервана.")
            return False
        for block in chunker.feed(to_int16(frame)):
            percent = enroll_percent(profiler.enroll(block))
            if int(percent) != last_sent:
                last_sent = int(percent)
                emit("enroll_progress", percent=round(percent, 1))
            if percent >= 100.0:
                break
    if hasattr(profiler, "flush"):
        try:
            profiler.flush()
        except Exception:  # noqa: BLE001
            pass
    profile = profiler.export()
    with open(out_path, "wb") as handle:
        handle.write(profile.to_bytes())
    emit("enroll_done", path=out_path)
    try:
        profiler.delete()
    except Exception:  # noqa: BLE001
        pass
    return True


def _float(value, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default
