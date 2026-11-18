#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -d "$APP_ROOT/gerania.xcodeproj" || -d "$APP_ROOT/Gerania.xcodeproj" ]]; then
    PROJECT_ROOT="$APP_ROOT"
else
    PROJECT_ROOT="$(cd "$APP_ROOT/.." && pwd)"
fi

PACKAGE="$APP_ROOT/Packages/GeraniaKit"
SCRATCH="$PROJECT_ROOT/build/swiftpm"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "== swift build =="
swift build --package-path "$PACKAGE" --scratch-path "$SCRATCH"

echo "== swift test =="
swift test --package-path "$PACKAGE" --scratch-path "$SCRATCH"

echo "== gerania-cli =="
swift run --package-path "$PACKAGE" --scratch-path "$SCRATCH" gerania-cli

if command -v swiftformat >/dev/null 2>&1; then
    echo "== swiftformat =="
    swiftformat "$PACKAGE" "$APP_ROOT/GeraniaApp.swift" --lint
fi

if command -v swiftlint >/dev/null 2>&1; then
    echo "== swiftlint =="
    (cd "$APP_ROOT" && swiftlint lint --quiet)
fi

# Окружение голоса живёт вне папки приложения (см. scripts/setup_voice.sh).
VOICE_VENV="${GERANIA_VOICE_VENV:-$HOME/Library/Application Support/Gerania/voice-venv}"
PYTHON="$VOICE_VENV/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    PYTHON="$(command -v python3 || true)"
fi
if [[ -d "$APP_ROOT/tools/voice_tests" && -n "$PYTHON" ]]; then
    echo "== python tests =="
    if "$PYTHON" -c "import pytest" >/dev/null 2>&1; then
        # Кэш pytest и байт-код не должны попадать в синхронизируемую папку:
        # Xcode копирует её в Resources, и одинаковые имена ломают сборку.
        PYTHONDONTWRITEBYTECODE=1 "$PYTHON" -m pytest "$APP_ROOT/tools/voice_tests" -q \
            -p no:cacheprovider
    else
        echo "pytest не установлен — тесты голоса пропущены (поставьте через scripts/setup_voice.sh)"
    fi
fi

echo "== voice script =="
# Скрипт «ушей» — обычный ресурс: опечатка в нём не ломает сборку, но глушит голос.
# Проверяем синтаксис отдельно, чтобы такое ловилось до запуска приложения.
"$PYTHON" -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' \
    "$APP_ROOT/Resources/Voice/gera_ears.py"
echo "gera_ears.py: синтаксис в порядке"

echo "== cleanup =="
# Кэш питона попадает в ресурсы приложения — убираем его перед сборкой.
find "$APP_ROOT/tools" "$APP_ROOT/Resources" -name "*.pyc" -delete 2>/dev/null || true
find "$APP_ROOT/tools" "$APP_ROOT/Resources" -name "__pycache__" -type d -empty -delete 2>/dev/null || true
find "$APP_ROOT/tools" "$APP_ROOT/Resources" -name ".pytest_cache" -type d -empty -delete 2>/dev/null || true

echo "== app build =="
"$SCRIPT_DIR/build.sh" Debug
