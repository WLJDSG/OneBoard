#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/OneBoard"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/OneBoard.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$PROJECT_DIR"
: "${ONEBOARD_BUILD_HOME:=/private/tmp/oneboard-home}"
: "${ONEBOARD_MODULE_CACHE:=/private/tmp/oneboard-module-cache}"
export HOME="$ONEBOARD_BUILD_HOME"
export CLANG_MODULE_CACHE_PATH="$ONEBOARD_MODULE_CACHE"
swift build -c release --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/OneBoard" "$MACOS_DIR/OneBoard"
sed 's/$(EXECUTABLE_NAME)/OneBoard/g' "Resources/Info.plist" > "$CONTENTS_DIR/Info.plist"

if [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

chmod +x "$MACOS_DIR/OneBoard"
echo "Built $APP_DIR"
