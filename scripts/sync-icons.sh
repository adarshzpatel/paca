#!/usr/bin/env bash
# Copy the Phosphor icons Paca uses (phosphoricons.com, MIT) into Sources/Paca/Resources/Icons.
# Add a name to ICONS and a case to `Icon` in Sources/Paca/Icon.swift, then rerun.
#
#   scripts/sync-icons.sh                      clones phosphor-icons/core into a temp dir
#   scripts/sync-icons.sh ~/src/phosphor-core  uses an existing checkout
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=(
  caret-down check clock-counter-clockwise columns folder folder-open gear-six git-branch
  globe-simple house lightning magnifying-glass palette plugs plus plus-circle rows
  sidebar-simple sparkle terminal-window trash tray warning warning-circle x
)
WEIGHTS=(bold fill)

core="${1:-}"
if [[ -z "$core" ]]; then
  core="$(mktemp -d)/core"
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/phosphor-icons/core "$core"
  git -C "$core" sparse-checkout set "${WEIGHTS[@]/#/assets/}" >/dev/null
fi

OUT=Sources/Paca/Resources/Icons
rm -rf "$OUT"
mkdir -p "$OUT"
for name in "${ICONS[@]}"; do
  for weight in "${WEIGHTS[@]}"; do
    # NSImage's SVG reader doesn't resolve currentColor. Icons are template images, so any
    # opaque color works: SwiftUI tints them with foregroundStyle.
    sed 's/currentColor/#000/g' "$core/assets/$weight/$name-$weight.svg" > "$OUT/ph-$name-$weight.svg"
  done
done
echo "icons synced: ${#ICONS[@]} icons x ${#WEIGHTS[@]} weights in $OUT"
