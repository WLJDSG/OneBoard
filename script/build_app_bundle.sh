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
if [ -z "${ONEBOARD_CODESIGN_IDENTITY:-}" ]; then
    ONEBOARD_CODESIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/Developer ID Application|Apple Development/ { print $2; exit }')"
fi
: "${ONEBOARD_CODESIGN_IDENTITY:=-}"
export HOME="$ONEBOARD_BUILD_HOME"
export CLANG_MODULE_CACHE_PATH="$ONEBOARD_MODULE_CACHE"
swift build -c release --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/OneBoard" "$MACOS_DIR/OneBoard"
chmod +x "$MACOS_DIR/OneBoard"
sed 's/$(EXECUTABLE_NAME)/OneBoard/g' "Resources/Info.plist" > "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 开发模式：通过环境变量追加后缀，避免污染正式 Bundle ID
# 示例：ONEBOARD_BUNDLE_ID_SUFFIX=.dev → com.oneboard.mac.dev
if [ -n "${ONEBOARD_BUNDLE_ID_SUFFIX:-}" ]; then
    CURRENT_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$CONTENTS_DIR/Info.plist")"
    NEW_ID="${CURRENT_ID}${ONEBOARD_BUNDLE_ID_SUFFIX}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${NEW_ID}" "$CONTENTS_DIR/Info.plist"
    echo "🔧 Bundle ID = $NEW_ID (suffix=${ONEBOARD_BUNDLE_ID_SUFFIX})"
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

echo "Signing LaunchAtLogin helper and OneBoard.app with identity: $ONEBOARD_CODESIGN_IDENTITY"
/usr/bin/codesign --force --deep --sign "$ONEBOARD_CODESIGN_IDENTITY" "$HELPER_APP"
/usr/bin/codesign --force --deep --sign "$ONEBOARD_CODESIGN_IDENTITY" "$APP_DIR"

echo "Validating app bundle..."
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
echo "Main bundle id: $APP_BUNDLE_ID"
echo "Helper bundle id: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$HELPER_APP/Contents/Info.plist")"

echo "Built $APP_DIR"
