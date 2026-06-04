# Screenshot, Permission, Clipboard Follow-up Spec

## Scope

修复 2026-06-04 11:42 录屏反馈中的问题：

- 截图窗口拖动应稳定跟手，不再因为本地窗口坐标变化产生抖动。
- 文字工具点击后应能输入文字；切换到其他工具时应退出空文字输入框，不能阻塞绘制或窗口拖动。
- 授权成功后权限引导悬浮窗应自动关闭，并刷新设置页状态。
- 剪贴板 fileURL 记录只接收普通文件、文件夹和常见压缩包；不记录 `.app` 等应用包。
- 权限引导中的 OneBoard.app 拖拽项不应进入剪贴板历史。
- 完成后重新打包 `build/OneBoard.dmg`。

## Non-goals

- 不改 OCR、翻译、暂存区摇晃检测、剪贴板 UI 布局。
- 不删除已有剪贴板文本/图片历史能力；本次只限制 fileURL 中的应用包和非普通文件包。
- 不处理签名和公证。

## Verification

- `HOME=/private/tmp/oneboard-home CLANG_MODULE_CACHE_PATH=/private/tmp/oneboard-module-cache swift build`
- `./script/package_app.sh`
- `hdiutil imageinfo build/OneBoard.dmg`
- 挂载 DMG 检查 `OneBoard.app` 和 `Applications` 链接。
