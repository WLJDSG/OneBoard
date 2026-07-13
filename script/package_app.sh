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

# 创建可双击运行的卸载脚本
UNINSTALL_CMD="$DMG_ROOT/卸载残留.command"
UNINSTALL_SCRIPT="$DMG_ROOT/.oneboard-uninstall.sh"
cp "$ROOT_DIR/script/uninstall.sh" "$UNINSTALL_SCRIPT"
chmod +x "$UNINSTALL_SCRIPT"
cat > "$UNINSTALL_CMD" << 'UNINSTALL_EOF'
#!/bin/bash
echo "🧹 OneBoard 残留清理工具"
echo "========================="
echo ""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/.oneboard-uninstall.sh"
echo ""
read -p "按回车键退出..."
UNINSTALL_EOF
chmod +x "$UNINSTALL_CMD"
echo "📦 DMG 已添加卸载脚本"

hdiutil create \
    -volname "OneBoard" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_ROOT" "$APP_DIR"

echo "Packaged $DMG_PATH"
