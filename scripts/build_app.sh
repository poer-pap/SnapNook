#!/bin/sh
set -eu

CONFIGURATION="${1:-debug}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/SnapNook.app"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/SnapNook"
APP_IDENTIFIER="com.ethan.snapnook"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/SnapNook"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/SnapNook.icns" "$APP_DIR/Contents/Resources/SnapNook.icns"
cp "$ROOT_DIR/Resources/SnapNookMenuBarTemplate.png" "$APP_DIR/Contents/Resources/SnapNookMenuBarTemplate.png"
codesign --force --sign - --identifier "$APP_IDENTIFIER" "$APP_DIR/Contents/MacOS/SnapNook"
codesign --force --deep --sign - --identifier "$APP_IDENTIFIER" "$APP_DIR"

echo "$APP_DIR"
