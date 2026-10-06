#!/usr/bin/env bash
# Build a release Paca.app and install it so it opens from Launchpad or Spotlight.
#
#   scripts/install.sh                 installs to /Applications/Paca.app
#   scripts/install.sh ~/Applications  installs somewhere else
#
# The version is a timestamp, so About Paca and Finder's Get Info show which
# build you are testing.
set -euo pipefail
cd "$(dirname "$0")/.."

dest_dir="${1:-/Applications}"
app="$dest_dir/Paca.app"
version="0.1.$(date +%Y%m%d%H%M)"

# Fail before building or stopping the running app if the native icon cannot compile.
# PACA_ICON_FALLBACK=1 installs with the flat brand/app-icons/Paca.icns instead (no Xcode needed;
# the Dock shows the plain icon rather than the layered macOS 26 one).
if [[ "${PACA_ICON_FALLBACK:-}" == 1 ]] && ! xcrun --find actool >/dev/null 2>&1; then
  mkdir -p .build/app-icon
  cp brand/app-icons/Paca.icns .build/app-icon/Paca.icns
  rm -f .build/app-icon/Assets.car
  echo "Using the flat icon (PACA_ICON_FALLBACK=1, no Xcode)." >&2
else
  scripts/build-app-icon.sh
fi
swift build -c release --product Paca >/dev/null
bin_dir="$(swift build -c release --show-bin-path)"

stage="$(mktemp -d)/Paca.app"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
cp "$bin_dir/Paca" "$stage/Contents/MacOS/Paca"
cp .build/app-icon/Paca.icns "$stage/Contents/Resources/"
# The layered icon's asset catalog exists only when Xcode compiled it.
if [[ -s .build/app-icon/Assets.car ]]; then cp .build/app-icon/Assets.car "$stage/Contents/Resources/"; fi
# Resource bundles go in Contents/Resources: anything at the bundle root blocks code signing.
# Brand.swift looks there first; SwiftTerm's bundle only feeds its optional Metal renderer.
cp -R "$bin_dir/Paca_Paca.bundle" "$stage/Contents/Resources/"
cp -R "$bin_dir/SwiftTerm_SwiftTerm.bundle" "$stage/Contents/Resources/"
# In-app uses of Brand.appIcon should match the generated fallback, too.
cp .build/app-icon/Paca.icns "$stage/Contents/Resources/Paca_Paca.bundle/Paca.icns"

cat > "$stage/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Paca</string>
    <key>CFBundleDisplayName</key><string>Paca</string>
    <key>CFBundleIdentifier</key><string>local.paca.Paca</string>
    <key>CFBundleExecutable</key><string>Paca</string>
    <key>CFBundleIconFile</key><string>Paca</string>
    <key>CFBundleIconName</key><string>Paca</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: macOS refuses notifications from unsigned apps.
codesign --force --deep --sign - "$stage" >/dev/null

# Quit a running copy so the new build replaces it cleanly.
osascript -e 'tell application id "local.paca.Paca" to quit' >/dev/null 2>&1 || true
pkill -x Paca >/dev/null 2>&1 || true

rm -rf "$app"
mv "$stage" "$app"
touch "$app"
echo "Installed Paca $version at $app"
