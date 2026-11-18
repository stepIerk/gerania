#!/usr/bin/env bash
# Старый скрипт оставлен для привычки: вся сборка иконки живёт в make_icon.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/make_icon.sh" "$@"
