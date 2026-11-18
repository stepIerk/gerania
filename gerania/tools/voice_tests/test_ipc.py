"""IPC: кодирование событий и обработка команд приложения."""
import json

from conftest import ears


def test_events_are_ndjson(ipc, capsys):
    ipc.emit("ready", model="mlx-community/whisper-large-v3-turbo")
    ipc.emit("transcript", text="Гера", no_speech=0.1, logprob=-0.5)

    out = capsys.readouterr().out
    lines = [line for line in out.splitlines() if line.strip()]

    assert len(lines) == 2
    first = json.loads(lines[0])
    assert first["type"] == "ready"
    assert first["model"].startswith("mlx-community")
    second = json.loads(lines[1])
    assert second["type"] == "transcript"
    assert second["text"] == "Гера"
    assert second["no_speech"] == 0.1


def test_state_command_sets_busy_and_speaking(ipc):
    ipc.apply({"type": "state", "busy": True, "speaking": False})

    assert ipc.busy is True
    assert ipc.speaking is False

    ipc.apply({"type": "state", "busy": False, "speaking": True})

    assert ipc.busy is False
    assert ipc.speaking is True


def test_mute_command_makes_the_microphone_deaf(ipc):
    before = ipc.deaf_until()
    ipc.apply({"type": "mute", "sec": 0.45})

    assert ipc.deaf_until() > before


def test_mute_keeps_the_phrase_by_default(ipc):
    """Звук приложения не должен рвать фразу: по умолчанию VAD не сбрасываем."""
    ipc.apply({"type": "mute", "sec": 0.2})

    assert ipc.mute_keep_phrase is True


def test_hard_mute_can_reset_the_phrase(ipc):
    ipc.apply({"type": "mute", "sec": 0.2, "keep_phrase": False})

    assert ipc.mute_keep_phrase is False


def test_arm_and_disarm(ipc):
    ipc.apply({"type": "arm"})
    assert ears.State.awaiting is True

    ipc.apply({"type": "disarm"})
    assert ears.State.awaiting is False


def test_levels_switch(ipc):
    ipc.apply({"type": "levels_on"})
    assert ipc.levels_on is True

    ipc.apply({"type": "levels_off"})
    assert ipc.levels_on is False


def test_config_overrides_thresholds(ipc):
    ipc.apply({"type": "config", "values": {"min_rms": 0.02, "await_command_sec": 5}})

    assert ears.MIN_RMS == 0.02
    assert ears.AWAIT_COMMAND_SEC == 5


def test_shutdown_sets_the_exit_flag(ipc):
    ipc.apply({"type": "shutdown"})

    assert ipc.should_exit is True


def test_unknown_command_is_ignored(ipc):
    ipc.apply({"type": "что-то-неизвестное"})

    assert ipc.busy is False
    assert ipc.should_exit is False
