#!/usr/bin/env bash
# Screenshots of Paca for posts and the README, taken against the demo session from
# scripts/demo-session.sh (rebuilt first, so every run starts from the same state).
#
#   scripts/demo-shots.sh                      PNGs in .build/demo-shots
#   scripts/demo-shots.sh ~/Desktop/paca       somewhere else
#   SIZE=1600x1000 scripts/demo-shots.sh       another window size (points)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${1:-.build/demo-shots}
SIZE=${SIZE:-1440x900}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

scripts/demo-session.sh >/dev/null
swift build --product Paca >/dev/null

# The snapshot renders the layer tree, which can't see Metal-drawn terminals, so these
# runs use the CPU renderer. A plist value, because Paca reads the setting as a Bool.
shot() { # name, extra Paca arguments...
  local name=$1; shift
  .build/debug/Paca --snapshot "$OUT/$name.png" --session paca-demo --window-size "$SIZE" \
    --snapshot-delay 5 -terminal.metal '<false/>' "$@" 2>&1 | grep -q "snapshot written" \
    && echo "  $name.png" || echo "  $name.png FAILED" >&2
}

# Background tabs first; the last --select is the one on screen.
TABS=w2:p1,w1:p1

echo "screenshots in $OUT:"
shot 01-home --view home --select "$TABS"
shot 02-needs-you --view inbox --select w1:p1,w2:p1
# Click into the terminal, then ⌘D opens the split with the previous tab.
shot 03-split --view home --select w1:p3,w1:p1 --click 900,400 --keys cmd+d --snapshot-delay 7
shot 04-palette --view home --select "$TABS" --palette "pa"
shot 05-paca-light --view home --select "$TABS" --theme paca-light
shot 06-catppuccin --view home --select "$TABS" --theme catppuccin
shot 07-tokyo-night --view home --select "$TABS" --theme tokyo-night
shot 08-rose-pine --view home --select "$TABS" --theme rose-pine
