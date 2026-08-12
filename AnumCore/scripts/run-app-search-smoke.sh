#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANUM_CORE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANUM_ROOT="$(cd "${ANUM_CORE_DIR}/.." && pwd)"

FEDERATION_SERVER_DIR="${FEDERATION_SERVER_DIR:-${ANUM_ROOT}/../../Projects/unify-federation/federation-server}"
PORT="${PORT:-8787}"
BASE_URL="${UNIFY_DEBUG_FEDERATION_BASE_URL:-http://127.0.0.1:${PORT}}"

echo "[app-search-smoke] Phase 4H-1 preflight"
echo "[app-search-smoke] Ensuring local federation catalog is seeded via Phase 4F script…"

FEDERATION_SERVER_DIR="${FEDERATION_SERVER_DIR}" \
UNIFY_DEBUG_FEDERATION_BASE_URL="${BASE_URL}" \
"${ANUM_CORE_DIR}/scripts/run-retrieval-local-federation-smoke.sh" >/tmp/anum-app-search-smoke-preflight.log 2>&1 || {
  echo "[app-search-smoke] Phase 4F preflight failed; see /tmp/anum-app-search-smoke-preflight.log" >&2
  tail -30 /tmp/anum-app-search-smoke-preflight.log >&2 || true
  exit 1
}

cat <<EOF

[app-search-smoke] Local federation server is ready at ${BASE_URL}

Simulator DEBUG launch checklist:
1. Xcode → Scheme → Run → Environment Variables:
   UNIFY_DEBUG_FEDERATION_BASE_URL=${BASE_URL}
2. Optional launch automation:
   ANUM_APP_SEARCH_SMOKE=1
3. Run on iOS Simulator (4H-1 simulator-only)
4. Profile shell → App search smoke → Run

Or launch with both env vars for one-shot automation after deferred exchange boot.

Console markers:
  [AppSearchSmoke]
  [APP-SEARCH-SMOKE]
  [APP-SEARCH-SMOKE-AGGREGATE]

Artifact (simulator):
  Documents/Artifacts/app_search_smoke_audit.jsonl

EOF

if [[ "${ANUM_APP_SEARCH_SMOKE_LAUNCH:-}" == "1" ]]; then
  SIM_ID="${SIM_ID:-}"
  if [[ -z "${SIM_ID}" ]]; then
    SIM_ID="$(xcrun simctl list devices available | rg -m1 'iPhone 16 Pro \(' | rg -o '[A-F0-9-]{36}')"
  fi
  if [[ -z "${SIM_ID}" ]]; then
    echo "[app-search-smoke] ANUM_APP_SEARCH_SMOKE_LAUNCH=1 but no simulator ID found; set SIM_ID" >&2
    exit 1
  fi

  DERIVED_DATA="${ANUM_APP_SEARCH_SMOKE_DERIVED_DATA:-/tmp/anum-app-search-smoke-dd}"
  APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/AnumAPP.app"
  CONSOLE_LOG="${ANUM_APP_SEARCH_SMOKE_CONSOLE_LOG:-/tmp/anum-app-search-smoke-console.log}"

  echo "[app-search-smoke] building Debug simulator app…"
  xcodebuild -scheme AnumAPP \
    -project "${ANUM_ROOT}/AnumAPP/AnumAPP.xcodeproj" \
    -destination "platform=iOS Simulator,id=${SIM_ID}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -configuration Debug \
    build >/tmp/anum-app-search-smoke-build.log 2>&1

  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "${APP_PATH}/Info.plist")"
  echo "[app-search-smoke] booting simulator ${SIM_ID}"
  xcrun simctl boot "${SIM_ID}" 2>/dev/null || true
  open -a Simulator --args -CurrentDeviceUDID "${SIM_ID}" 2>/dev/null || true
  xcrun simctl install "${SIM_ID}" "${APP_PATH}"

  xcrun simctl spawn "${SIM_ID}" launchctl setenv UNIFY_DEBUG_FEDERATION_BASE_URL "${BASE_URL}"
  xcrun simctl spawn "${SIM_ID}" launchctl setenv ANUM_APP_SEARCH_SMOKE "1"

  : > "${CONSOLE_LOG}"
  echo "[app-search-smoke] launching ${BUNDLE_ID} (console -> ${CONSOLE_LOG})"
  xcrun simctl launch \
    --terminate-running-process \
    --console \
    "${SIM_ID}" \
    "${BUNDLE_ID}" \
    -UNIFY_DEBUG_FEDERATION_BASE_URL "${BASE_URL}" \
    >> "${CONSOLE_LOG}" 2>&1 &
  echo "[app-search-smoke] launch pid=$! bundle=${BUNDLE_ID}"
  echo "[app-search-smoke] watch for [APP-SEARCH-SMOKE-AGGREGATE] in ${CONSOLE_LOG}"
fi
