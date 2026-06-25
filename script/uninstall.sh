#!/bin/bash
# OneBoard 卸载脚本 —— 清理所有残留文件
set -euo pipefail

BUNDLE_ID="${ONEBOARD_BUNDLE_ID:-com.oneboard.mac}"
APP_PATH="/Applications/OneBoard.app"

echo "🧹 OneBoard 卸载脚本"
echo "   Bundle ID: $BUNDLE_ID"
echo ""

# ---- 1. 停止运行中的应用 ----
if pgrep -x OneBoard > /dev/null; then
    echo "⏹  停止 OneBoard..."
    pkill -x OneBoard 2>/dev/null || true
    sleep 1
fi

# ---- 2. 删除应用 ----
if [ -d "$APP_PATH" ]; then
    echo "🗑  删除 $APP_PATH"
    rm -rf "$APP_PATH"
fi

# 也清理 build 目录下的临时 app
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$PROJECT_DIR/build/OneBoard.app" ]; then
    rm -rf "$PROJECT_DIR/build/OneBoard.app"
fi

# ---- 3. 清理 UserDefaults ----
echo "🧹 清理 UserDefaults..."
defaults delete "$BUNDLE_ID" 2>/dev/null || true

# ---- 4. 清理 TCC 隐私权限 ----
echo "🧹 清理隐私权限..."
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true

# ---- 5. 清理 Control Center 状态栏记录 ----
echo "🧹 清理菜单栏状态..."
python3 -c "
import plistlib, os

path = os.path.expanduser('~/Library/Preferences/com.apple.controlcenter.plist')
if os.path.exists(path):
    with open(path, 'rb') as f:
        pl = plistlib.load(f)
    removed = [k for k in list(pl.keys()) if 'oneboard' in str(k).lower()]
    for k in removed:
        del pl[k]
    with open(path, 'wb') as f:
        plistlib.dump(pl, f)
    print(f'  已删除 {len(removed)} 条 Control Center 记录')
else:
    print('  无需清理')
" 2>/dev/null

# ---- 6. 清理辅助功能授权记录 ----
echo "🧹 清理辅助功能记录..."
python3 -c "
import plistlib, os

path = os.path.expanduser('~/Library/Preferences/com.apple.universalaccessAuthWarning.plist')
if os.path.exists(path):
    with open(path, 'rb') as f:
        pl = plistlib.load(f)
    removed = [k for k in list(pl.keys()) if 'oneboard' in str(k).lower()]
    for k in removed:
        del pl[k]
    with open(path, 'wb') as f:
        plistlib.dump(pl, f)
    print(f'  已删除 {len(removed)} 条辅助功能记录')
else:
    print('  无需清理')
" 2>/dev/null

# ---- 7. 清理 Spotlight ----
echo "🧹 清理 Spotlight..."
python3 -c "
import plistlib, os

path = os.path.expanduser('~/Library/Preferences/com.apple.corespotlightui.plist')
if os.path.exists(path):
    with open(path, 'rb') as f:
        pl = plistlib.load(f)
    if 'CSReceiverBundleIdentifierState' in pl:
        removed = [k for k in list(pl['CSReceiverBundleIdentifierState'].keys()) if 'oneboard' in str(k).lower()]
        for k in removed:
            del pl['CSReceiverBundleIdentifierState'][k]
        with open(path, 'wb') as f:
            plistlib.dump(pl, f)
        print(f'  已删除 {len(removed)} 条 Spotlight 记录')
    else:
        print('  无需清理')
else:
    print('  无需清理')
" 2>/dev/null

# ---- 8. 清理缓存 ----
echo "🧹 清理缓存..."
rm -rf ~/Library/Caches/"$BUNDLE_ID" 2>/dev/null || true
rm -rf ~/Library/Application\ Support/"$BUNDLE_ID" 2>/dev/null || true
rm -rf ~/Library/Saved\ Application\ State/"$BUNDLE_ID".savedState 2>/dev/null || true
rm -rf ~/Library/HTTPStorages/"$BUNDLE_ID" 2>/dev/null || true

# ---- 9. 重启系统服务 ----
echo "🔄 重启系统服务..."
killall cfprefsd ControlCenter Dock 2>/dev/null || true

echo ""
echo "✅ OneBoard 卸载完成！"
echo ""
echo "💡 提示：Launch Services 数据库残留需要重启 Mac 后才能完全清"
echo "   除。如果你计划重新安装同一个 Bundle ID，建议先重启再安装。"
