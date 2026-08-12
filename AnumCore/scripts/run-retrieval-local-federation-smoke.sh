#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANUM_CORE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANUM_ROOT="$(cd "${ANUM_CORE_DIR}/.." && pwd)"

FEDERATION_SERVER_DIR="${FEDERATION_SERVER_DIR:-${ANUM_ROOT}/../../Projects/unify-federation/federation-server}"
PORT="${PORT:-8787}"
BASE_URL="${UNIFY_DEBUG_FEDERATION_BASE_URL:-http://127.0.0.1:${PORT}}"
CATALOG_JSON="${ANUM_CATALOG_EXPORT_PATH:-/tmp/anum-retrieval-accuracy-catalog.json}"
MANIFEST_JSON="${ANUM_LOCAL_FED_SMOKE_GENERATION_FILE:-/tmp/anum-local-fed-smoke-generation.json}"
SERVER_PID=""
STARTED_SERVER=0

cleanup() {
  if [[ "${STARTED_SERVER}" == "1" && -n "${SERVER_PID}" ]]; then
    echo "[local-fed-smoke] stopping federation-server pid=${SERVER_PID}"
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -d "${FEDERATION_SERVER_DIR}" ]]; then
  echo "[local-fed-smoke] federation server dir not found: ${FEDERATION_SERVER_DIR}" >&2
  echo "Set FEDERATION_SERVER_DIR to your federation-server checkout." >&2
  exit 1
fi

if lsof -i ":${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  if [[ "${SKIP_SERVER_START:-}" == "1" ]]; then
    echo "[local-fed-smoke] assuming server already listening on :${PORT}"
  else
    echo "[local-fed-smoke] port ${PORT} already in use; set SKIP_SERVER_START=1 or free the port" >&2
    exit 1
  fi
else
  if [[ "${SKIP_SERVER_START:-}" != "1" ]]; then
    if [[ "${SKIP_DB_RESET:-}" != "1" ]]; then
      echo "[local-fed-smoke] resetting SQLite database"
      rm -f "${FEDERATION_SERVER_DIR}/data/federation.sqlite" \
        "${FEDERATION_SERVER_DIR}/data/federation.sqlite-shm" \
        "${FEDERATION_SERVER_DIR}/data/federation.sqlite-wal"
    fi
    echo "[local-fed-smoke] starting federation-server on :${PORT}"
    (
      cd "${FEDERATION_SERVER_DIR}"
      UNIFY_RATE_LIMIT_PROFILE=smoke PORT="${PORT}" npm start
    ) >/tmp/anum-local-fed-server.log 2>&1 &
    SERVER_PID=$!
    STARTED_SERVER=1
    for _ in $(seq 1 60); do
      if curl -sf "${BASE_URL}/health" >/dev/null 2>&1; then
        break
      fi
      sleep 0.5
    done
    if ! curl -sf "${BASE_URL}/health" >/dev/null 2>&1; then
      echo "[local-fed-smoke] server failed to become healthy; log:" >&2
      tail -50 /tmp/anum-local-fed-server.log >&2 || true
      exit 1
    fi
    echo "[local-fed-smoke] server healthy at ${BASE_URL}"
  fi
fi

echo "[local-fed-smoke] exporting ONNX fixture catalog"
(
  cd "${ANUM_CORE_DIR}"
  ANUM_EXPORT_RETRIEVAL_ACCURACY_CATALOG=1 \
  ANUM_CATALOG_EXPORT_PATH="${CATALOG_JSON}" \
  ANUM_LOCAL_FED_SMOKE_GENERATION_FILE="${MANIFEST_JSON}" \
  swift test --filter 'ExchangeRetrievalLocalFederationSmokeTests/exportCatalogWhenRequested'
)

echo "[local-fed-smoke] seeding catalog through HTTP publish routes"
if [[ "${RESET_SMOKE_FIXTURES:-}" == "1" ]]; then
  echo "[local-fed-smoke] resetting retrieval-accuracy fixture nodes before seed"
  (
    cd "${FEDERATION_SERVER_DIR}"
    DB_PATH="${FEDERATION_SERVER_DIR}/data/federation.sqlite" \
    ANUM_CATALOG_EXPORT_PATH="${CATALOG_JSON}" \
    ANUM_LOCAL_FED_SMOKE_GENERATION_FILE="${MANIFEST_JSON}" \
    node scripts/reset-retrieval-accuracy-fixture-nodes.js \
      --catalog "${CATALOG_JSON}" \
      --manifest "${MANIFEST_JSON}"
  )
fi
(
  cd "${FEDERATION_SERVER_DIR}"
  node scripts/seed-retrieval-accuracy-catalog.js \
    --baseUrl "${BASE_URL}" \
    --catalog "${CATALOG_JSON}" \
    --manifest "${MANIFEST_JSON}"
)

echo "[local-fed-smoke] verifying SQLite seed"
(
  cd "${FEDERATION_SERVER_DIR}"
  DB_PATH="${FEDERATION_SERVER_DIR}/data/federation.sqlite" \
  ANUM_LOCAL_FED_SMOKE_GENERATION_FILE="${MANIFEST_JSON}" \
  node scripts/verify-retrieval-accuracy-seed.js --manifest "${MANIFEST_JSON}"
)

echo "[local-fed-smoke] running Swift local federation smoke audit"
(
  cd "${ANUM_CORE_DIR}"
  ANUM_RETRIEVAL_LOCAL_FEDERATION_SMOKE=1 \
  UNIFY_DEBUG_FEDERATION_BASE_URL="${BASE_URL}" \
  ANUM_LOCAL_FED_SMOKE_GENERATION_FILE="${MANIFEST_JSON}" \
  ANUM_LOCAL_FED_SMOKE_FULL="${ANUM_LOCAL_FED_SMOKE_FULL:-}" \
  swift test --filter 'ExchangeRetrievalLocalFederationSmokeTests/localFederationRetrievalSmoke'
)

echo "[local-fed-smoke] complete"
