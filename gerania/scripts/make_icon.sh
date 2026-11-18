#!/usr/bin/env bash
# Собирает иконку приложения из картинки пользователя.
#
#   scripts/make_icon.sh [путь/к/исходнику.png]
#
# Что делает:
#   1. мастер 1024×1024: цветок на тёмном сквирле (tools/icon/make_icon.swift);
#   2. AppIcon.appiconset — 10 размеров + Contents.json (для Xcode);
#   3. GeraIcon.icns — то, что macOS показывает в Dock и в Finder;
#   4. копия .icns рядом с исходником: папка gerania/ синхронизируется с таргетом,
#      поэтому иконка попадает в Contents/Resources бандла (ключ CFBundleIconFile).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -d "$APP_ROOT/gerania.xcodeproj" || -d "$APP_ROOT/Gerania.xcodeproj" ]]; then
    PROJECT_ROOT="$APP_ROOT"
else
    PROJECT_ROOT="$(cd "$APP_ROOT/.." && pwd)"
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

SOURCE="${1:-$APP_ROOT/GeraniaIcon.png}"
BUILD="$PROJECT_ROOT/build"
MASTER="$BUILD/icon-master.png"
ICONSET="$APP_ROOT/Assets.xcassets/AppIcon.appiconset"
ICONS_DIR="$BUILD/GeraIcon.iconset"
# Имя не AppIcon: actool назовёт свою иконку AppIcon.icns, иначе будет конфликт имён.
ICNS="$APP_ROOT/GeraIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
    echo "Не найден исходник иконки: $SOURCE" >&2
    echo "Положите квадратный PNG (например 1024×1024) и повторите." >&2
    exit 1
fi

mkdir -p "$BUILD" "$ICONSET"

echo "== мастер =="
swift "$PROJECT_ROOT/tools/icon/make_icon.swift" "$SOURCE" "$MASTER"

echo "== размеры для каталога =="
emit() {
    local pixels="$1" filename="$2"
    sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/$filename" >/dev/null
}
emit 16 "icon_16x16.png"
emit 32 "icon_16x16@2x.png"
emit 32 "icon_32x32.png"
emit 64 "icon_32x32@2x.png"
emit 128 "icon_128x128.png"
emit 256 "icon_128x128@2x.png"
emit 256 "icon_256x256.png"
emit 512 "icon_256x256@2x.png"
emit 512 "icon_512x512.png"
emit 1024 "icon_512x512@2x.png"

cat >"$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "== icns =="
rm -rf "$ICONS_DIR"
mkdir -p "$ICONS_DIR"
for size in 16 32 128 256 512; do
    cp "$ICONSET/icon_${size}x${size}.png" "$ICONS_DIR/icon_${size}x${size}.png"
    cp "$ICONSET/icon_${size}x${size}@2x.png" "$ICONS_DIR/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONS_DIR" -o "$ICNS"

echo "Готово:"
echo "  каталог: $ICONSET"
echo "  иконка:  $ICNS"
