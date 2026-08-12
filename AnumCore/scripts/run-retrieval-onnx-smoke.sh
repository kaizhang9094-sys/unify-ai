#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ANUM_RETRIEVAL_ONNX_SMOKE=1
if [[ "${ANUM_RETRIEVAL_ONNX_SMOKE_EXTENDED:-}" == "1" ]]; then
  echo "Running extended ONNX retrieval smoke (14 scenarios)"
else
  echo "Running mandatory ONNX retrieval smoke (10 scenarios)"
fi
swift test --filter ExchangeRetrievalOnnxSmokeTests
