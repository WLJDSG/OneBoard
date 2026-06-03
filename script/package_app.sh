#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/OneBoard.app"
DMG_ROOT="$BUILD_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/OneBoard.dmg"

"$ROOT_DIR/script/build_app_bundle.sh"

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/OneBoard.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
    -volname "OneBoard" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_ROOT" "$APP_DIR"

echo "Packaged $DMG_PATH"
