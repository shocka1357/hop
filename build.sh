#!/bin/bash
# Builds Hop.app. Run "./build.sh install" to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Hop.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos26.0" Sources/*.swift -o "$APP/Contents/MacOS/Hop"
cp Info.plist "$APP/Contents/"

if [ ! -f build/AppIcon.icns ]; then
  swift Tools/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x Hop || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Hop.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Hop.app
  echo "Installed to ~/Applications/Hop.app"
fi
