#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -d "$APP_ROOT/gerania.xcodeproj" || -d "$APP_ROOT/Gerania.xcodeproj" ]]; then
    PROJECT_ROOT="$APP_ROOT"
else
    PROJECT_ROOT="$(cd "$APP_ROOT/.." && pwd)"
fi

"$SCRIPT_DIR/build.sh" Release

SOURCE="$PROJECT_ROOT/build/DerivedData/Build/Products/Release/gerania.app"
DESTINATION="/Applications/Gerania.app"

if [[ ! -d "$SOURCE" ]]; then
    echo "Не найдено приложение: $SOURCE" >&2
    exit 1
fi

mkdir -p "$DESTINATION"
ditto "$SOURCE/" "$DESTINATION/"

echo "Установлено в $DESTINATION"
open "$DESTINATION"
