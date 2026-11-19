"""Listen modes and the pluggable wake word (no Picovoice, no network)."""
import sys

import numpy as np

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


def test_wake_is_ignored_while_gera_speaks_and_in_push_to_talk():
    assert wake.wake_allowed(wake.LISTEN_ALWAYS, speaking=False)
    assert not wake.wake_allowed(wake.LISTEN_ALWAYS, speaking=True)
    assert not wake.wake_allowed(wake.LISTEN_PUSH_TO_TALK, speaking=False)


# --- audio plumbing -----------------------------------------------------------

def test_frames_are_chunked_to_the_engine_block():
    chunker = wake.Chunker(512)
    frame = np.full(480, 0.5, dtype=np.float32)

    blocks = list(chunker.feed(frame)) + list(chunker.feed(frame))

    assert len(blocks) == 1
    assert blocks[0].size == 512
    assert int(wake.to_int16(blocks[0])[0]) == 16383


# --- custom wake model ----------------------------------------------------------

def test_without_a_plugin_the_wake_word_is_whisper():
    assert wake.load_wake_plugin({}) == (None, "Whisper")


def test_missing_plugin_file_falls_back_to_whisper(tmp_path):
    detector, detail = wake.load_wake_plugin({"GERA_WAKE_PLUGIN": str(tmp_path / "none.py")})
    assert detector is None
    assert detail.startswith("Whisper")


def test_plugin_module_is_loaded(tmp_path):
    module = tmp_path / "my_wake.py"
    module.write_text(
        "class D:\n"
        "    name = 'тест'\n"
        "    def feed(self, frame):\n        return True\n"
        "    def reset(self):\n        pass\n"
        "def create(environ):\n    return D()\n",
        encoding="utf-8",
    )

    detector, detail = wake.load_wake_plugin({"GERA_WAKE_PLUGIN": str(module)})

    assert detector is not None
    assert detector.feed(np.zeros(480, dtype=np.float32)) is True
    assert detail == "своя модель: тест"


def test_broken_plugin_does_not_stop_the_ears(tmp_path):
    module = tmp_path / "broken.py"
    module.write_text("def create(environ):\n    raise RuntimeError('boom')\n", encoding="utf-8")

    detector, detail = wake.load_wake_plugin({"GERA_WAKE_PLUGIN": str(module)})

    assert detector is None
    assert "boom" in detail


# --- IPC commands ---------------------------------------------------------------

def test_ipc_listen_mode_and_flush(ipc):
    ipc.apply({"type": "listen_mode", "mode": "push_to_talk"})
    ipc.apply({"type": "flush"})

    assert ipc.listen_mode == wake.LISTEN_PUSH_TO_TALK
    assert ears.State.flush is True


def test_ipc_ignores_unknown_listen_mode(ipc):
    ipc.apply({"type": "listen_mode", "mode": "telepathy"})
    assert ipc.listen_mode == wake.LISTEN_ALWAYS
