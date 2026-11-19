"""Porcupine, Eagle and the listen modes, with fake engines (no Picovoice needed)."""
import sys
import types

import numpy as np
import pytest

from conftest import ears

wake = sys.modules["gera_wake"]


# --- listen modes -------------------------------------------------------------

def test_always_hears_everything():
    assert wake.frame_is_heard(wake.LISTEN_ALWAYS, busy=True, speaking=True, awaiting=False)


def test_not_while_answering_is_deaf_during_the_answer():
    mode = wake.LISTEN_NOT_WHILE_ANSWERING
    assert not wake.frame_is_heard(mode, busy=True, speaking=False, awaiting=False)
    assert not wake.frame_is_heard(mode, busy=False, speaking=True, awaiting=False)
    assert wake.frame_is_heard(mode, busy=False, speaking=False, awaiting=False)
    # The hotkey arms the ears even during the answer.
    assert wake.frame_is_heard(mode, busy=True, speaking=True, awaiting=True)


def test_push_to_talk_hears_only_after_the_hotkey():
    mode = wake.LISTEN_PUSH_TO_TALK
    assert not wake.frame_is_heard(mode, busy=False, speaking=False, awaiting=False)
    assert wake.frame_is_heard(mode, busy=False, speaking=False, awaiting=True)


def test_voice_barge_in_needs_the_owner_gate():
    assert wake.wake_allowed(wake.LISTEN_ALWAYS, speaking=False, owner_gate=False)
    assert not wake.wake_allowed(wake.LISTEN_ALWAYS, speaking=True, owner_gate=False)
    assert wake.wake_allowed(wake.LISTEN_ALWAYS, speaking=True, owner_gate=True)
    assert not wake.wake_allowed(wake.LISTEN_NOT_WHILE_ANSWERING, speaking=True, owner_gate=True)
    assert not wake.wake_allowed(wake.LISTEN_PUSH_TO_TALK, speaking=False, owner_gate=True)


# --- audio plumbing -----------------------------------------------------------

def test_float_frames_become_int16_and_are_chunked():
    chunker = wake.Chunker(512)
    frame = np.full(480, 0.5, dtype=np.float32)

    blocks = list(chunker.feed(wake.to_int16(frame))) + list(chunker.feed(wake.to_int16(frame)))

    assert len(blocks) == 1
    assert blocks[0].dtype == np.int16
    assert blocks[0].size == 512
    assert int(blocks[0][0]) == 16383


# --- Porcupine ----------------------------------------------------------------

class FakePorcupine:
    frame_length = 512

    def __init__(self, hit_after_blocks: int):
        self.calls = 0
        self.hit_after = hit_after_blocks

    def process(self, pcm):
        self.calls += 1
        return 0 if self.calls == self.hit_after else -1

    def delete(self):
        pass


def test_keyword_detector_reports_the_frame_with_the_word():
    detector = wake.KeywordDetector(FakePorcupine(hit_after_blocks=3))
    frame = np.zeros(480, dtype=np.float32)

    hits = [detector.feed(frame) for _ in range(4)]

    # 4 × 480 samples = 3 full blocks of 512: the third block ends in frame 4.
    assert hits == [False, False, False, True]


def test_keyword_detector_explains_why_it_is_off(tmp_path):
    assert wake.KeywordDetector.create({})[1] == "нет ключа Picovoice"
    assert "ppn" in wake.KeywordDetector.create({"GERA_PV_ACCESS_KEY": "k"})[1]
    keyword = tmp_path / "gera.ppn"
    keyword.write_bytes(b"x")
    env = {"GERA_PV_ACCESS_KEY": "k", "GERA_WAKE_KEYWORD": str(keyword),
           "GERA_WAKE_MODEL": str(tmp_path / "missing.pv")}
    assert "pv" in wake.KeywordDetector.create(env)[1]


# --- Eagle --------------------------------------------------------------------

class FakeRecognizerV1:
    frame_length = 512

    def __init__(self, score):
        self.score = score

    def process(self, pcm):
        return [self.score]

    def reset(self):
        pass


class FakeRecognizerV3:
    min_process_samples = 1024

    def __init__(self, score):
        self.score = score
        self.profiles_seen = None

    def process(self, pcm, profiles):
        self.profiles_seen = profiles
        return [self.score]


@pytest.mark.parametrize("score, owner", [(0.9, True), (0.1, False)])
def test_owner_verifier_v1(score, owner):
    verifier = wake.OwnerVerifier(FakeRecognizerV1(score), profile="p",
                                  profiles_in_process=False, threshold=0.5)
    for _ in range(3):
        verifier.feed(np.zeros(480, dtype=np.float32))
    assert verifier.is_owner() is owner


def test_owner_verifier_v3_passes_the_profile_to_process():
    engine = FakeRecognizerV3(0.8)
    verifier = wake.OwnerVerifier(engine, profile="p", profiles_in_process=True, threshold=0.5)
    for _ in range(3):
        verifier.feed(np.zeros(480, dtype=np.float32))
    assert engine.profiles_seen == ["p"]
    assert verifier.is_owner()


def test_owner_gate_uses_the_best_recent_score():
    gate = wake.OwnerGate(threshold=0.5, window=3)
    for score in (0.2, 0.7, 0.1):
        gate.add(score)
    assert gate.is_owner()
    for score in (0.1, 0.1, 0.1):
        gate.add(score)
    assert not gate.is_owner()


def test_speaker_tracker_reports_only_changes():
    tracker = wake.SpeakerTracker(other_after=0.4, silence_after=0.8)

    assert tracker.update(voiced=True, owner=True, now=0.0) == "owner"
    assert tracker.update(voiced=True, owner=True, now=0.1) is None
    assert tracker.update(voiced=True, owner=False, now=0.2) is None
    assert tracker.update(voiced=True, owner=False, now=0.7) == "other"
    assert tracker.update(voiced=False, owner=False, now=0.8) is None
    assert tracker.update(voiced=False, owner=False, now=1.7) == "silence"


class Profile:
    def to_bytes(self):
        return b"voice"


class FakeProfilerV1:
    min_enroll_samples = 1000

    def __init__(self):
        self.percent = 0.0

    def enroll(self, pcm):
        self.percent = min(100.0, self.percent + 50.0)
        return self.percent, "AUDIO_OK"

    def export(self):
        return Profile()

    def delete(self):
        pass


class FakeProfilerV3(FakeProfilerV1):
    frame_length = 512
    flushed = False

    def enroll(self, pcm):
        self.percent = min(100.0, self.percent + 25.0)
        return self.percent

    def flush(self):
        self.flushed = True


@pytest.mark.parametrize("profiler", [FakeProfilerV1(), FakeProfilerV3()])
def test_enrollment_writes_the_profile(tmp_path, profiler):
    events = []
    out = tmp_path / "owner.eagle"

    ok = wake.enroll_owner(str(out), lambda: np.zeros(480, dtype=np.float32),
                           lambda kind, **fields: events.append((kind, fields)), profiler=profiler)

    assert ok
    assert out.read_bytes() == b"voice"
    assert events[-1][0] == "enroll_done"
    assert any(kind == "enroll_progress" and fields["percent"] == 100.0 for kind, fields in events)


def test_enrollment_stops_when_audio_ends(tmp_path):
    events = []

    ok = wake.enroll_owner(str(tmp_path / "x"), lambda: None,
                           lambda kind, **fields: events.append(kind), profiler=FakeProfilerV1())

    assert not ok
    assert events == ["error"]


# --- IPC commands ---------------------------------------------------------------

def test_ipc_listen_mode_owner_gate_and_flush(ipc):
    ipc.apply({"type": "listen_mode", "mode": "push_to_talk"})
    ipc.apply({"type": "owner_gate", "enabled": False})
    ipc.apply({"type": "flush"})

    assert ipc.listen_mode == wake.LISTEN_PUSH_TO_TALK
    assert ipc.owner_gate is False
    assert ears.State.flush is True
    ears.State.flush = False


def test_ipc_ignores_unknown_listen_mode(ipc):
    ipc.apply({"type": "listen_mode", "mode": "telepathy"})
    assert ipc.listen_mode == wake.LISTEN_ALWAYS
