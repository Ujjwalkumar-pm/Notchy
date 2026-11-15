#!/bin/bash
# Builds the CAPTURE build used for the launch videos: the app compiled with -D NOTCHY_CAPTURE
# (demo-data harness, Sources/Notchy/CaptureHarness.swift), bundled as /tmp/NotchyCapture.app
# under its own bundle id so it never shares the real app's defaults, TCC grants, port or
# login item. It is never installed to /Applications. The release build (scripts/bundle.sh)
# does not contain the harness.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release -Xswiftc -DNOTCHY_CAPTURE --scratch-path .build-capture
BIN="$(swift build -c release -Xswiftc -DNOTCHY_CAPTURE --scratch-path .build-capture --show-bin-path)/Notchy"

APP="/tmp/NotchyCapture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchyCapture"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier in.ujjwalkumar.notchy.capture" \
    -c "Set :CFBundleExecutable NotchyCapture" \
    -c "Set :CFBundleShortVersionString ${CAPTURE_VERSION:-1.0.0}" "$APP/Contents/Info.plist"
# No Now Playing adapter: the capture build can never read or control a real player.
codesign --force --sign - "$APP"
echo "$APP"
