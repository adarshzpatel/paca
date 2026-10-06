#!/usr/bin/env bash
# Compile the layered Icon Composer document into native macOS app resources.
# Usage: scripts/build-app-icon.sh [OUTPUT_DIRECTORY]+# Set DEVELOPER_DIR if Xcode is installed outside /Applications/Xcode.app.
set -euo pipefail
cd "$(dirname "$0")/.."

output="${1:-.build/app-icon}"
source_icon="$PWD/brand/app-icons/Paca.icon"

# SwiftPM also works with Command Line Tools, but actool requires full Xcode.
# Select it only for this process; do not change the machine's xcode-select setting.
if ! xcrun --find actool >/dev/null 2>&1; then
  if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Native Paca icons require Xcode 26 or later, including actool." >&2
  echo "Install Xcode, complete its first launch, then rerun this command." >&2
  echo "For another Xcode location, set DEVELOPER_DIR to its Contents/Developer directory." >&2
  echo "The existing app and icons have not been replaced." >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
xcrun actool "$source_icon" \
  --compile "$stage" \
  --app-icon Paca \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target 14.0 \
  --enable-on-demand-resources NO \
  --output-partial-info-plist "$stage/icon-info.plist" \
  --output-format human-readable-text \
  --errors --warnings --notices

# A PNG or ICNS alone cannot carry the native layers.
test -s "$stage/Assets.car"
test -s "$stage/Paca.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$stage/icon-info.plist")" = Paca
mkdir -p "$output"
cp "$stage/Assets.car" "$stage/Paca.icns" "$stage/icon-info.plist" "$output/"
echo "Native Paca icon compiled into $output"
