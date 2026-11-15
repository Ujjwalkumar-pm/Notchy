#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-signing-cert.sh

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Notchy"

APP=".build/Notchy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notchy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/mediaremote-adapter "$APP/Contents/Resources/"

codesign --force --sign "Notchy Local Signing" --options runtime --entitlements Resources/Notchy.entitlements "$APP"

pkill -x Notchy || true
sleep 0.5
rm -rf /Applications/Notchy.app
cp -R "$APP" /Applications/Notchy.app
echo "/Applications/Notchy.app"
