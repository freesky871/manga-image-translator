#!/usr/bin/env bash
set -euo pipefail

PORTS="${PORTS:-8002 8004 8006 8008 8010}"
FIRST_PORT="${FIRST_PORT:-8002}"
ROOT="${ROOT:-/app}"
LOG_DIR="${LOG_DIR:-/workspace/logs}"
ENV_FILE="${ENV_FILE:-/workspace/.hm101_env}"

# model files
MODEL_BASE_URL="${MODEL_BASE_URL:-https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3}"
MODEL_FALLBACK_PREFIXES="${MODEL_FALLBACK_PREFIXES:-https://ghfast.top/ https://ghproxy.com/}"
MODEL_LIST="${MODEL_LIST:-/app/models/detection/detect-20241225.ckpt /app/models/ocr/ocr_ar_48px.ckpt /app/models/ocr/alphabet-all-v7.txt /app/models/inpainting/inpainting_lama_mpe.ckpt}"

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

download_one_model() {
  local model_path="$1"
  local model_dir model_name primary ok u
  model_dir="$(dirname "${model_path}")"
  model_name="$(basename "${model_path}")"
  primary="${MODEL_BASE_URL%/}/${model_name}"

  mkdir -p "${model_dir}"
  rm -f "${model_path}.part" "${model_path}" || true
  rm -f "${model_dir}"/*.part || true

  ok=""
  for u in "${primary}" $(for px in ${MODEL_FALLBACK_PREFIXES}; do echo "${px}${primary}"; done); do
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 1200 -o "${model_path}" "${u}"; then
      ok="${u}"
      break
    fi
  done

  if [ -z "${ok}" ] || [ ! -s "${model_path}" ]; then
    echo "[hm101] model download failed: ${model_name}"
    return 1
  fi

  echo "[hm101] model ready: ${model_name} <- ${ok}"
  return 0
}

start_worker() {
  local p="$1"
  nohup bash -lc "set -a; [ -f '${ENV_FILE}' ] && . '${ENV_FILE}'; set +a; exec '${PYBIN}' server/main.py --host 0.0.0.0 --port '${p}' --start-instance --use-gpu --nonce None" \
    >"${LOG_DIR}/mit_${p}.log" 2>&1 &
  echo "[hm101] worker started on ${p}"
}

wait_http_ready() {
  local p="$1" i
  for i in $(seq 1 90); do
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

# full model preheat
for m in ${MODEL_LIST}; do
  download_one_model "${m}"
done

# compatibility alias
if [ -s /app/models/inpainting/inpainting_lama_mpe.ckpt ] && [ ! -s /app/models/inpainting/lama_large_512px.ckpt ]; then
  cp -f /app/models/inpainting/inpainting_lama_mpe.ckpt /app/models/inpainting/lama_large_512px.ckpt || true
fi

# stage 1: single worker
start_worker "${FIRST_PORT}"
wait_http_ready "${FIRST_PORT}"

# stage 2: remaining workers
for p in ${PORTS}; do
  [ "${p}" = "${FIRST_PORT}" ] && continue
  start_worker "${p}"
done

echo "[hm101] all workers launched: ${PORTS}"
exit 0
