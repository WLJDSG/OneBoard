#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/OneBoard"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/OneBoard.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LOGIN_ITEMS_DIR="$CONTENTS_DIR/Library/LoginItems"

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

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

mkdir -p "$LOGIN_ITEMS_DIR"
HELPER_ZIP="$PROJECT_DIR/.build/checkouts/LaunchAtLogin/Sources/LaunchAtLogin/LaunchAtLoginHelper.zip"
HELPER_APP="$LOGIN_ITEMS_DIR/LaunchAtLoginHelper.app"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$CONTENTS_DIR/Info.plist")"

if [ -f "$HELPER_ZIP" ]; then
    rm -rf "$HELPER_APP"
    unzip -q "$HELPER_ZIP" -d "$LOGIN_ITEMS_DIR"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_ID}-LaunchAtLoginHelper" "$HELPER_APP/Contents/Info.plist"
else
    echo "Missing LaunchAtLogin helper zip: $HELPER_ZIP" >&2
    exit 1
fi

echo "Signing LaunchAtLogin helper and OneBoard.app..."
/usr/bin/codesign --force --deep --sign - "$HELPER_APP"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Validating app bundle..."
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
echo "Main bundle id: $APP_BUNDLE_ID"
echo "Helper bundle id: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$HELPER_APP/Contents/Info.plist")"

chmod +x "$MACOS_DIR/OneBoard"
echo "Built $APP_DIR"
