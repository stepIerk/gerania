#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQUIREMENTS="$APP_ROOT/Resources/Voice/requirements.txt"
# Окружение живёт ВНЕ папки приложения: Xcode копирует папку app-таргета в
# Resources, и миллион файлов venv ломает сборку (duplicate output file).
VENV="${GERANIA_VOICE_VENV:-$HOME/Library/Application Support/Gerania/voice-venv}"
BUNDLE_ID="${GERANIA_BUNDLE_ID:-com.sykorn.gerania}"

if [[ ! -f "$REQUIREMENTS" ]]; then
    echo "Не найден $REQUIREMENTS" >&2
    exit 1
fi

PYTHON="${1:-$(command -v python3 || true)}"
if [[ -z "$PYTHON" || ! -x "$PYTHON" ]]; then
    echo "Укажите Python: scripts/setup_voice.sh /path/to/python3" >&2
    exit 1
fi

mkdir -p "$(dirname "$VENV")"
"$PYTHON" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install -r "$REQUIREMENTS"

# Модели Whisper качаем заранее: большая — для финального текста, маленькая — для
# быстрого распознавания на ходу (Гера просыпается за доли секунды).
if "$VENV/bin/python" -c "import mlx_whisper" >/dev/null 2>&1; then
    echo "Качаем модели Whisper (это нужно один раз)..."
    "$VENV/bin/python" - <<'PYMODELS' || echo "Не удалось скачать модели — скачаются при первом запуске."
import numpy as np
import mlx_whisper

for model in ("mlx-community/whisper-large-v3-turbo", "mlx-community/whisper-base-mlx"):
    print(model, flush=True)
    mlx_whisper.transcribe(
        np.zeros(16000, dtype=np.float32),
        path_or_hf_repo=model,
        language="ru",
        verbose=False,
    )
PYMODELS
fi

# Приложение читает путь к python из своих настроек — записываем его туда,
# чтобы Геря сразу нашла окружение с numpy и mlx-whisper.
if command -v defaults >/dev/null 2>&1; then
    defaults write "$BUNDLE_ID" pythonPath -string "$VENV/bin/python" || true
    echo "Путь к python записан в настройки Gerania ($BUNDLE_ID)."
fi

echo "Готово. Python для настроек Геры: $VENV/bin/python"
echo "Проверка: \"$VENV/bin/python\" -c 'import numpy, mlx_whisper, sounddevice; print(\"ok\")'"
