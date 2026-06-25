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
cat > "$UNINSTALL_CMD" << 'UNINSTALL_EOF'
#!/bin/bash
echo "🧹 OneBoard 残留清理工具"
echo "========================="
echo ""
cd "$(dirname "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/../script/uninstall.sh" 2>/dev/null || {
    # 如果在 DMG 中运行，使用内置逻辑
    BUNDLE_ID="com.oneboard.mac"
    echo "⏹  停止 OneBoard..."
    pkill -x OneBoard 2>/dev/null || true
    sleep 1
    echo "🧹 清理 UserDefaults..."
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    echo "🧹 清理隐私权限..."
    tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
    echo "🧹 清理菜单栏状态..."
    python3 -c "
import plistlib, os
for f in ['com.apple.controlcenter.plist','com.apple.universalaccessAuthWarning.plist','com.apple.corespotlightui.plist']:
    p=os.path.expanduser(f'~/Library/Preferences/{f}')
    if os.path.exists(p):
        with open(p,'rb') as fh: pl=plistlib.load(fh)
        if isinstance(pl,dict):
            removed=[k for k in list(pl.keys()) if 'oneboard' in str(k).lower()]
            if 'CSReceiverBundleIdentifierState' in pl:
                removed+=[k for k in list(pl['CSReceiverBundleIdentifierState'].keys()) if 'oneboard' in str(k).lower()]
                pl['CSReceiverBundleIdentifierState']={k:v for k,v in pl['CSReceiverBundleIdentifierState'].items() if 'oneboard' not in str(k).lower()}
            for k in removed:
                if k in pl: del pl[k]
            with open(p,'wb') as fh: plistlib.dump(pl,fh)
    " 2>/dev/null
    rm -rf ~/Library/Caches/"$BUNDLE_ID" ~/Library/Application\ Support/"$BUNDLE_ID" 2>/dev/null
    killall cfprefsd ControlCenter 2>/dev/null || true
    echo ""
    echo "✅ 残留已清理！请将 OneBoard.app 拖入垃圾桶，然后重启 Mac。"
}
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
