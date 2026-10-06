#!/usr/bin/env bash
# Render Paca's main window to a PNG (no Screen Recording permission needed).
#
#   scripts/snapshot.sh                                   default session, nothing selected
#   scripts/snapshot.sh out.png --session paca-test --select w1:p1
#   scripts/snapshot.sh out.png --session paca-test --select w1:p1,w1:p2   several tabs
#
# Selecting a pane attaches to it, so only use --select on a test session
# unless you mean to take control of that pane.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-.build/snapshots/paca.png}
shift || true
mkdir -p "$(dirname "$OUT")"
swift build --product Paca >/dev/null
.build/debug/Paca --snapshot "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" "$@"
