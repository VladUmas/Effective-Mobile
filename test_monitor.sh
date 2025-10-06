#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
PATH=/usr/sbin:/usr/bin:/sbin:/bin

PROCESS_NAME="test"
ENDPOINT="https://test.com/monitoring/test/api"
LOG_FILE="/var/log/monitoring.log"
STATE_DIR="/var/run/test-monitor"
STATE_FILE="${STATE_DIR}/state"
LOCK_FILE="${STATE_DIR}/lock"

mkdir -p "${STATE_DIR}"

log() {
  local msg="$1"
  local stamp
  stamp="$(date '+%Y-%m-%d %H:%M:%S%z')"
  printf '%s %s\n' "$stamp" "$msg" >> "$LOG_FILE" || true
  logger -t test-monitor -p user.notice -- "$msg" || true
}

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  exit 0
fi

pids="$(pgrep -x -- "${PROCESS_NAME}" || true)"
[[ -n "$pids" ]] || exit 0
pid="$(printf '%s\n' "$pids" | head -n1)"
[[ -d "/proc/${pid}" ]] || exit 0

stat_line="$(cat "/proc/${pid}/stat" 2>/dev/null || true)"
[[ -n "$stat_line" ]] || exit 0
rest="${stat_line#*) }"
start_id="$(awk '{print $20}' <<< "$rest" 2>/dev/null || echo "")"
[[ -n "$start_id" ]] || exit 0

prev_pid=""
prev_start_id=""
if [[ -f "$STATE_FILE" ]]; then
  read -r prev_pid prev_start_id < "$STATE_FILE" || true
fi

if [[ -n "$prev_start_id" && "$start_id" != "$prev_start_id" ]]; then
  log "Процесс '${PROCESS_NAME}' был перезапущен (PID ${prev_pid} -> ${pid})."
fi

printf '%s %s\n' "$pid" "$start_id" > "$STATE_FILE"

if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 7 -o /dev/null "$ENDPOINT"; then
  log "Сервер мониторинга недоступен или вернул ошибку: ${ENDPOINT}"
fi
