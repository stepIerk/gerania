#!/usr/bin/env bash
# Живая проверка цепочки «план → запуск → файл результата» на ВРЕМЕННОМ HERMES_HOME.
# Реальные задачи пользователя не трогаются: всё живёт в mktemp-папке и удаляется в конце.
# Задача без LLM (--no-agent + скрипт), поэтому не нужен ни ключ модели, ни gateway.
#
#   scripts/cron_smoke.sh            # путь к hermes берётся из PATH
#   HERMES_BIN=/path/to/hermes scripts/cron_smoke.sh
set -euo pipefail

HERMES="${HERMES_BIN:-$(command -v hermes || true)}"
if [[ -z "$HERMES" ]]; then
    echo "hermes не найден в PATH — задайте HERMES_BIN" >&2
    exit 1
fi

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gerania-test-hermes.XXXXXX")"
trap 'rm -rf "$TMP_HOME"' EXIT
export HERMES_HOME="$TMP_HOME"
CRON="$HERMES_HOME/cron"
mkdir -p "$HERMES_HOME/scripts"
cat >"$HERMES_HOME/scripts/gerania-test-echo.sh" <<'EOF'
#!/bin/sh
echo "Гера: тестовое напоминание сработало"
EOF
chmod +x "$HERMES_HOME/scripts/gerania-test-echo.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

job_field() {
    # job_field <name> <python-expression over job>
    /usr/bin/env python3 - "$CRON/jobs.json" "$1" "$2" <<'PY'
import json, sys
path, name, expr = sys.argv[1:4]
jobs = json.load(open(path, encoding="utf-8-sig")).get("jobs", [])
job = next((j for j in jobs if j.get("name") == name), None)
print("" if job is None else eval(expr, {}, {"job": job}))
PY
}

echo "== hermes: $("$HERMES" --version 2>/dev/null | head -1)"
echo "== HERMES_HOME=$HERMES_HOME"

echo "== create"
"$HERMES" cron create "every 1m" --name gerania-test-reminder --deliver local \
    --script gerania-test-echo.sh --no-agent >/dev/null
[[ -f "$CRON/jobs.json" ]] || fail "jobs.json не появился"
ID="$(job_field gerania-test-reminder 'job["id"]')"
[[ -n "$ID" ]] || fail "задача не найдена в jobs.json"
echo "id=$ID kind=$(job_field gerania-test-reminder 'job["schedule"]["kind"]')" \
    "next_run_at=$(job_field gerania-test-reminder 'job.get("next_run_at")')" \
    "state=$(job_field gerania-test-reminder 'job.get("state")')"
[[ -n "$(job_field gerania-test-reminder 'job.get("next_run_at") or ""')" ]] || fail "нет next_run_at"

echo "== one-shot schedule (in 2m)"
"$HERMES" cron create "in 2m" "gerania-test once" --name gerania-test-once --deliver local >/dev/null
[[ "$(job_field gerania-test-once 'job["schedule"]["kind"]')" == "once" ]] || fail "'in 2m' не стал once"

echo "== pause / resume"
"$HERMES" cron pause "$ID" >/dev/null
[[ "$(job_field gerania-test-reminder 'job.get("state")')" == "paused" ]] || fail "пауза не применилась"
"$HERMES" cron resume "$ID" >/dev/null
[[ "$(job_field gerania-test-reminder 'job.get("state")')" == "scheduled" ]] || fail "resume не применился"

echo "== run now + tick"
"$HERMES" cron run "$ID" >/dev/null
"$HERMES" cron tick >/dev/null 2>&1 || true
OUT="$(find "$CRON/output/$ID" -name '*.md' 2>/dev/null | head -1)"
[[ -n "$OUT" ]] || fail "после tick нет cron/output/$ID/*.md (см. hermes cron list)"
head -1 "$OUT" | grep -q '^# Cron Job: ' || fail "формат результата изменился: $(head -1 "$OUT")"
grep -q "тестовое напоминание" "$OUT" || fail "в результате нет вывода скрипта"
echo "output: $(basename "$OUT")"

echo "== remove"
"$HERMES" cron remove "$ID" >/dev/null
"$HERMES" cron remove "$(job_field gerania-test-once 'job["id"]')" >/dev/null
[[ -z "$(job_field gerania-test-reminder 'job["id"]')" ]] || fail "задача не удалилась"

echo "OK: cron create/pause/resume/run/tick/remove работают, формат результата совпадает с CronOutputDigest"
