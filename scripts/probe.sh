#!/usr/bin/env bash
# Smoke-check Paca's herdr connection without the GUI.
#
#   scripts/probe.sh                      snapshot of the default herdr session
#   scripts/probe.sh --session paca-test  snapshot of a named session
#   scripts/probe.sh watch                stream live events (ctrl+c to stop)
#   scripts/probe.sh frame w1:p1          attach to a pane, print the first frame, release
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product paca-probe >/dev/null
exec .build/debug/paca-probe "$@"
