#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -d "$APP_ROOT/gerania.xcodeproj" || -d "$APP_ROOT/Gerania.xcodeproj" ]]; then
    PROJECT_ROOT="$APP_ROOT"
else
    PROJECT_ROOT="$(cd "$APP_ROOT/.." && pwd)"
fi

PROJECT="$PROJECT_ROOT/gerania.xcodeproj"
if [[ ! -d "$PROJECT" ]]; then
    echo "Не найден gerania.xcodeproj рядом с $APP_ROOT" >&2
    exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

CONFIG="${1:-Debug}"
BUILD_DIR="$PROJECT_ROOT/build"
mkdir -p "$BUILD_DIR"

ARGS=(
    -project "$PROJECT"
    -scheme gerania
    -configuration "$CONFIG"
    -destination "platform=macOS,arch=arm64"
    -derivedDataPath "$BUILD_DIR/DerivedData"
    build
)

if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild "${ARGS[@]}" 2>&1 | xcbeautify
else
    xcodebuild "${ARGS[@]}"
fi

echo "Готово: $BUILD_DIR/DerivedData/Build/Products/$CONFIG/gerania.app"
