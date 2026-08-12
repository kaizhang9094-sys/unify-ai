#!/usr/bin/env bash
# Runs isolated provider H3 metadata tests without building broken AnumCoreTests.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --filter ProviderH3MetadataTests "$@"
