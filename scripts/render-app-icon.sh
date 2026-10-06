#!/usr/bin/env bash
# Preview the native source with Apple's renderer without rebuilding the app.
set -euo pipefail
cd "$(dirname "$0")/.."

composer="/Applications/Icon Composer.app"
if [[ ! -d "$composer" ]]; then
  developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
  composer="${developer_dir%/Developer}/Applications/Icon Composer.app"
fi
renderer="$composer/Contents/Executables/ictool"
if [[ ! -x "$renderer" ]]; then
  echo "Install Apple's Icon Composer or Xcode to render the icon previews." >&2
  exit 1
fi

output=brand/app-icons/native-previews
mkdir -p "$output"
renditions=(Default Dark ClearLight ClearDark TintedLight TintedDark)
names=(default dark clear-light clear-dark tinted-light tinted-dark)
for index in "${!renditions[@]}"; do
  "$renderer" brand/app-icons/Paca.icon --export-image \
    --output-file "$output/${names[$index]}.png" --platform macOS \
    --rendition "${renditions[$index]}" --width 256 --height 256 --scale 1
done
"$renderer" brand/app-icons/Paca.icon --export-image \
  --output-file "$output/default-1024.png" --platform macOS \
  --rendition Default --width 1024 --height 1024 --scale 1
for size in 32 64; do
  "$renderer" brand/app-icons/Paca.icon --export-image \
    --output-file "$output/dock-$size.png" --platform macOS \
    --rendition Default --width "$size" --height "$size" --scale 2
done
echo "Icon Composer previews rendered into $output"
