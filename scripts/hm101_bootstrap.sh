#!/usr/bin/env bash
set -euo pipefail

PORTS="${PORTS:-8002 8004 8006 8008 8010}"
FIRST_PORT="${FIRST_PORT:-8002}"
ROOT="${ROOT:-/app}"
LOG_DIR="${LOG_DIR:-/workspace/logs}"
ENV_FILE="${ENV_FILE:-/workspace/.hm101_env}"

find_root() {
  for d in /app /workspace /; do
    if [ -f "$d/server/main.py" ]; then
      echo "$d"
      return 0
    fi
  done
  local hit
  hit="$(find / -maxdepth 6 -path '*/server/main.py' 2>/dev/null | head -n 1 || true)"
  if [ -n "$hit" ]; then
    echo "$(cd "$(dirname "$hit")/.." && pwd)"
    return 0
  fi
  return 1
}

ROOT="$(find_root || true)"
if [ -z "${ROOT}" ]; then
  echo "[hm101] server/main.py not found"
  exit 1
fi

PYBIN="$(command -v python3 || command -v python || true)"
if [ -z "${PYBIN}" ]; then
  echo "[hm101] python not found"
  exit 2
fi

mkdir -p "${LOG_DIR}" /workspace || true
touch "${ENV_FILE}" || true
chmod 600 "${ENV_FILE}" || true

set -a
# shellcheck disable=SC1090
[ -f "${ENV_FILE}" ] && . "${ENV_FILE}"
set +a

start_worker() {
  local p="$1"
  nohup bash -lc "set -a; [ -f '${ENV_FILE}' ] && . '${ENV_FILE}'; set +a; exec '${PYBIN}' server/main.py --host 0.0.0.0 --port '${p}' --start-instance --use-gpu --nonce None" \
    >"${LOG_DIR}/mit_${p}.log" 2>&1 &
  echo "[hm101] worker started on ${p}"
}

wait_http_ready() {
  local p="$1" i
  for i in $(seq 1 120); do
    if curl -fsS --max-time 3 "http://127.0.0.1:${p}/" >/dev/null 2>&1; then
      echo "[hm101] worker ${p} http ready"
      return 0
    fi
    sleep 2
  done
  echo "[hm101] worker ${p} http not ready"
  return 1
}

cd "${ROOT}"

# 阶段1：先启动单 worker，确认服务可用
start_worker "${FIRST_PORT}"
wait_http_ready "${FIRST_PORT}"

# 阶段2：再启动其余 worker
for p in ${PORTS}; do
  [ "${p}" = "${FIRST_PORT}" ] && continue
  start_worker "${p}"
done

echo "[hm101] all workers launched: ${PORTS}"
exit 0
