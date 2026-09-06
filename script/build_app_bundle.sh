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
HELPERS_DIR="$CONTENTS_DIR/Helpers"
PROXY_MANIFEST="$ROOT_DIR/ProxySidecar/Cargo.toml"
PROXY_BINARY="$ROOT_DIR/ProxySidecar/target/release/oneboard-ai-proxy"

echo "Building embedded AI proxy..."
if [ ! -x "$PROXY_BINARY" ] \
    || [ "$PROXY_MANIFEST" -nt "$PROXY_BINARY" ] \
    || [ "$ROOT_DIR/ProxySidecar/Cargo.lock" -nt "$PROXY_BINARY" ] \
    || [ "$ROOT_DIR/ProxySidecar/src/main.rs" -nt "$PROXY_BINARY" ]; then
    env -u ONEBOARD_CODESIGN_IDENTITY cargo build --release --locked --manifest-path "$PROXY_MANIFEST"
else
    echo "Using current embedded AI proxy binary."
fi

cd "$PROJECT_DIR"
: "${ONEBOARD_BUILD_HOME:=/private/tmp/oneboard-home}"
: "${ONEBOARD_MODULE_CACHE:=/private/tmp/oneboard-module-cache}"
if [ -z "${ONEBOARD_CODESIGN_IDENTITY:-}" ]; then
    ONEBOARD_CODESIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/Developer ID Application|Apple Development/ { print $2; exit }')"
fi
: "${ONEBOARD_CODESIGN_IDENTITY:=-}"
HOME="$ONEBOARD_BUILD_HOME" \
CLANG_MODULE_CACHE_PATH="$ONEBOARD_MODULE_CACHE" \
swift build -c release --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR"

cp ".build/release/OneBoard" "$MACOS_DIR/OneBoard"
chmod +x "$MACOS_DIR/OneBoard"
cp "$PROXY_BINARY" "$HELPERS_DIR/oneboard-ai-proxy"
chmod +x "$HELPERS_DIR/oneboard-ai-proxy"
mkdir -p "$RESOURCES_DIR/ThirdPartyNotices"
cp "$ROOT_DIR/ThirdPartyNotices/CC-Switch-LICENSE.txt" "$RESOURCES_DIR/ThirdPartyNotices/CC-Switch-LICENSE.txt"
cp "$ROOT_DIR/ThirdPartyNotices/LunarSwift-LICENSE.txt" "$RESOURCES_DIR/ThirdPartyNotices/LunarSwift-LICENSE.txt"

# --- Finder Sync Extension ---
echo "Building Finder Sync Extension..."
FINDER_SYNC_BINARY="$BUILD_DIR/OneBoardFinderSync"
BUILD_ARCH="$(uname -m)"
CLANG_MODULE_CACHE_PATH="$ONEBOARD_MODULE_CACHE" xcrun swiftc \
    -O \
    -parse-as-library \
    -target "${BUILD_ARCH}-apple-macosx14.0" \
    "FinderSync/FinderSyncController.swift" \
    "Shared/FinderFileCreation.swift" \
    -framework Cocoa \
    -framework FinderSync \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    -o "$FINDER_SYNC_BINARY"

PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
EXTENSION_DIR="$PLUGINS_DIR/OneBoardFinderSync.appex"
mkdir -p "$EXTENSION_DIR/Contents/MacOS" "$EXTENSION_DIR/Contents/Resources"

cp "$FINDER_SYNC_BINARY" "$EXTENSION_DIR/Contents/MacOS/OneBoardFinderSync"
chmod +x "$EXTENSION_DIR/Contents/MacOS/OneBoardFinderSync"
cp "FinderSync/Info.plist" "$EXTENSION_DIR/Contents/Info.plist"

# 处理扩展 Info.plist 中的 Bundle ID（应用开发模式后缀）
if [ -n "${ONEBOARD_BUNDLE_ID_SUFFIX:-}" ]; then
    EXTENSION_CURRENT_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$EXTENSION_DIR/Contents/Info.plist")"
    EXTENSION_NEW_ID="${EXTENSION_CURRENT_ID}${ONEBOARD_BUNDLE_ID_SUFFIX}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${EXTENSION_NEW_ID}" "$EXTENSION_DIR/Contents/Info.plist"
fi

# 验证扩展结构
if [ ! -f "$EXTENSION_DIR/Contents/MacOS/OneBoardFinderSync" ]; then
    echo "ERROR: Finder Sync Extension binary missing!" >&2
    exit 1
fi
echo "Finder Sync Extension bundled at $EXTENSION_DIR"

sed 's/$(EXECUTABLE_NAME)/OneBoard/g' "Resources/Info.plist" > "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [ "${ONEBOARD_ENABLE_ICLOUD_SYNC:-0}" = "1" ]; then
    APP_ENTITLEMENTS="Resources/OneBoard.entitlements"
    /usr/libexec/PlistBuddy -c "Add :OneBoardCloudSyncAvailable bool true" "$CONTENTS_DIR/Info.plist"
else
    APP_ENTITLEMENTS="Resources/OneBoard.local.entitlements"
    /usr/libexec/PlistBuddy -c "Add :OneBoardCloudSyncAvailable bool false" "$CONTENTS_DIR/Info.plist"
    echo "iCloud sync signing is disabled for this local package."
fi

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 开发模式：通过环境变量追加后缀，避免污染正式 Bundle ID
# 开发 ID 可轮换；当 macOS 记住某个状态项的隐藏状态时，切换到新后缀。
# 示例：ONEBOARD_BUNDLE_ID_SUFFIX=.dev2 → com.oneboard.mac.dev2
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

echo "Signing with identity: $ONEBOARD_CODESIGN_IDENTITY"
# 先签名扩展（必须在主应用之前）
if [ -d "$EXTENSION_DIR" ]; then
    /usr/bin/codesign --force --sign "$ONEBOARD_CODESIGN_IDENTITY" --entitlements "FinderSync/OneBoardFinderSync.entitlements" "$EXTENSION_DIR" || true
fi
/usr/bin/codesign --force --sign "$ONEBOARD_CODESIGN_IDENTITY" "$HELPER_APP" || true
/usr/bin/codesign --force --sign "$ONEBOARD_CODESIGN_IDENTITY" "$HELPERS_DIR/oneboard-ai-proxy" || true
# 嵌套扩展已经按各自 entitlement 签名；这里不能使用 --deep 重签，
# 否则会剥掉 Finder 扩展的 app-sandbox entitlement，导致 PlugInKit 拒绝加载。
/usr/bin/codesign --force --sign "$ONEBOARD_CODESIGN_IDENTITY" --entitlements "$APP_ENTITLEMENTS" "$APP_DIR"

echo "Validating app bundle..."
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
echo "Main bundle id: $APP_BUNDLE_ID"
echo "Helper bundle id: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$HELPER_APP/Contents/Info.plist")"

echo "Built $APP_DIR"
