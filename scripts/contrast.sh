#!/usr/bin/env bash
# WCAG contrast audit of every theme as Paca draws it (built-ins plus ~/.config/paca/themes).
# Exits 1 if any pairing still misses its minimum after Paca's corrections.
#
#   scripts/contrast.sh              standard minimums, show corrected pairings
#   scripts/contrast.sh --all        show every pairing
#   scripts/contrast.sh --increased  minimums for macOS "Increase contrast"
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product paca-probe >/dev/null
exec .build/debug/paca-probe contrast "$@"
