#!/usr/bin/env bash
# Copy brand assets the app uses into Sources/Paca/Resources and build the app icon.
# Rerun after changing anything in brand/.
set -euo pipefail
cd "$(dirname "$0")/.."
# Native output and its older-macOS fallback both come from the same .icon source.
scripts/build-app-icon.sh
RES=Sources/Paca/Resources
mkdir -p "$RES/Fonts" brand/app-icons

cp brand/toolbar/paca-template.svg "$RES/paca-template.svg"
cp brand/logos/paca-wordmark-cream.svg brand/logos/paca-wordmark-ink.svg "$RES/"
cp brand/originals/paca-mascot-transparent.png "$RES/paca-mascot.png"
cp brand/fonts/manrope/Manrope-Variable.ttf brand/fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf \
   brand/fonts/ibm-plex-mono/IBMPlexMono-Medium.ttf "$RES/Fonts/"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
ICONSET="$scratch/Paca.iconset"
cp .build/app-icon/Paca.icns brand/app-icons/Paca.icns
iconutil -c iconset brand/app-icons/Paca.icns -o "$ICONSET"
cp "$ICONSET/icon_512x512@2x.png" brand/app-icons/paca-app-icon-1024.png
cp "$ICONSET/icon_128x128@2x.png" brand/app-icons/paca-app-icon-256.png
cp brand/app-icons/Paca.icns "$RES/Paca.icns"
cp brand/app-icons/paca-app-icon-256.png "$RES/paca-app-icon.png"
# Alternate Dock icons for Settings > App icon (512px is the largest the Dock draws).
for variant in charcoal lavender mint; do
  cp "brand/app-icons/paca-$variant-512.png" "$RES/paca-app-icon-$variant.png"
done
echo "brand synced from Paca.icon: $RES, brand/app-icons/Paca.icns"
