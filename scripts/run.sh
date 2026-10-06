#!/usr/bin/env bash
# Build and launch Paca.
#
#   scripts/run.sh                                  default herdr session
#   scripts/run.sh --session paca-test --select w1:p1
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Paca >/dev/null
exec .build/debug/Paca "$@"
