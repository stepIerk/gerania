"""Общие заглушки для тестов голосового фронтенда.

`mlx_whisper` и `sounddevice` не нужны для проверки логики wake/stop и IPC,
поэтому они подменяются через `sys.modules` до импорта скрипта.
"""
import importlib.util
import sys
import types
from pathlib import Path

# Модуль «ушей» лежит в ресурсах приложения — байт-код туда не пишем.
sys.dont_write_bytecode = True

import pytest

ROOT = Path(__file__).resolve().parents[2]
EARS_PATH = ROOT / "Resources" / "Voice" / "gera_ears.py"


def _install_stubs() -> None:
    if "mlx_whisper" not in sys.modules:
        mlx = types.ModuleType("mlx_whisper")

        def transcribe(audio, **kwargs):  # noqa: ANN001, ANN003
            return {"text": "", "segments": []}

        mlx.transcribe = transcribe
        sys.modules["mlx_whisper"] = mlx

    if "sounddevice" not in sys.modules:
        sounddevice = types.ModuleType("sounddevice")

        class InputStream:  # noqa: D101
            def __init__(self, *args, **kwargs):  # noqa: ANN002, ANN003
                self.args = args
                self.kwargs = kwargs

            def __enter__(self):
                return self

            def __exit__(self, *args):  # noqa: ANN002
                return False

        sounddevice.InputStream = InputStream
        sys.modules["sounddevice"] = sounddevice


def _load_ears():
    _install_stubs()
    spec = importlib.util.spec_from_file_location("gera_ears", EARS_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["gera_ears"] = module
    spec.loader.exec_module(module)
    return module


ears = _load_ears()


@pytest.fixture()
def ipc(monkeypatch):
    """IPC в режиме приложения: события пишутся в stdout."""
    monkeypatch.setattr(ears, "IPC_MODE", True)
    instance = ears.IPC()
    return instance


@pytest.fixture(autouse=True)
def _fresh_state():
    """`State` is class-level: a wake word of one test must not leak into the next."""
    ears.State.awaiting = False
    ears.State.await_deadline = 0.0
    ears.State.keyword_at = 0.0
    ears.State.flush = False
    yield
