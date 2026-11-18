#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -d "$APP_ROOT/gerania.xcodeproj" || -d "$APP_ROOT/Gerania.xcodeproj" ]]; then
    PROJECT_ROOT="$APP_ROOT"
else
    PROJECT_ROOT="$(cd "$APP_ROOT/.." && pwd)"
fi

"$SCRIPT_DIR/build.sh" Debug

APP="$PROJECT_ROOT/build/DerivedData/Build/Products/Debug/gerania.app"
SCREENS="$PROJECT_ROOT/build/screens"
mkdir -p "$SCREENS"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || echo "com.yourname.Gerania")"

# URL-схема живёт в Info.plist таргета, её добавляет человек (docs/HUMAN_TODO.md).
HAS_URL_SCHEME=0
if /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    HAS_URL_SCHEME=1
fi

pkill -x gerania >/dev/null 2>&1 || true
sleep 0.5

capture() {
    local name="$1"
    sleep "${2:-1.2}"
    if ! screencapture -x "$SCREENS/$name.png" 2>/dev/null; then
        echo "  ! screencapture не сработал (нет прав на запись экрана) — $name"
        return 0
    fi
    echo "  снимок: $SCREENS/$name.png"
}

state() {
    local name="$1"
    if [[ "$HAS_URL_SCHEME" == "1" ]]; then
        open "gerania://debug/state?name=$name"
    else
        open -n "$APP" --env GERA_DEBUG=1 --args "--gera-debug-state=$name"
    fi
}

stream() {
    local sample="$1"
    if [[ "$HAS_URL_SCHEME" == "1" ]]; then
        open "gerania://debug/stream?sample=$sample"
    else
        open -n "$APP" --env GERA_DEBUG=1 --args "--gera-debug-stream=$sample"
    fi
}

if [[ "$HAS_URL_SCHEME" == "1" ]]; then
    echo "== debug routes через gerania:// =="
    open -n "$APP" --env GERA_DEBUG=1 --args --gera-no-window
    sleep 2
else
    echo "== URL-схема не зарегистрирована: запуск с аргументами --gera-debug-* =="
    echo "   (добавьте gerania:// в Info таргета — docs/HUMAN_TODO.md)"
    open -n "$APP" --env GERA_DEBUG=1 --args --gera-no-window
    sleep 2
fi

echo "-- состояния --"
for name in listening heard thinking error done; do
    state "$name"
    capture "$name"
done

echo "-- поток ответа --"
stream markdown
capture "stream-markdown" 2.5
capture "stream-markdown-end" 2.0

stream long
capture "stream-long-mid" 1.6
capture "stream-long-end" 6.0

if [[ "$HAS_URL_SCHEME" == "1" ]]; then
    echo "-- окно ответа --"
    stream markdown
    sleep 4
    open "gerania://debug/detail"
    capture "answer-detail"
fi

echo "-- мини-окно ввода --"
# Прячем HUD, чтобы мини-окно встало на своё место.
if [[ "$HAS_URL_SCHEME" == "1" ]]; then
    open "gerania://stop"
else
    open -n "$APP" --env GERA_DEBUG=1 --args --gera-debug-state=idle
fi
sleep 1.5
if [[ "$HAS_URL_SCHEME" == "1" ]]; then
    open "gerania://input"
    capture "input-empty"
    open "gerania://input?text=Первая%20строка%0AВторая%20строка%0AТретья%20строка"
    capture "input-text"
    open "gerania://input?chats=1"
    capture "input-chats"
else
    open -n "$APP" --env GERA_DEBUG=1 --args --gera-debug-input
    capture "input-empty"
    open -n "$APP" --env GERA_DEBUG=1 --args "--gera-debug-input-text"
    capture "input-text"
    open -n "$APP" --env GERA_DEBUG=1 --args "--gera-debug-input-chats"
    capture "input-chats"
fi
pkill -x gerania >/dev/null 2>&1 || true

log show --last 2m --info --debug --style compact \
    --predicate "subsystem BEGINSWITH \"$BUNDLE_ID\"" \
    >"$SCREENS/log.txt" 2>/dev/null || true

pkill -x gerania >/dev/null 2>&1 || true

echo "Скриншоты: $SCREENS"
echo "Логи: $SCREENS/log.txt"
