# OneBoard Runtime Fixes Spec

## Scope

修复三个运行时问题，并补齐可拖拽安装的 DMG 打包方式：

- 点击菜单栏“设置...”不应闪退，且应稳定打开同一个设置窗口。
- 截图快捷键应能请求/检查屏幕录制权限，成功截取全屏并显示区域选择遮罩。
- 拖拽文件时只有检测到左右摇晃手势才唤出暂存区。
- 生成的 DMG 内应包含 `OneBoard.app` 和 `Applications` 软链接，用户可直接拖拽安装。

## Non-goals

- 不改动剪贴板数据库、OCR、翻译、标注工具的业务逻辑。
- 不引入 Xcode 工程；继续保持 SwiftPM 构建。
- 不处理签名/公证。

## UX Behavior

- 设置窗口通过菜单栏打开后置前；重复点击只聚焦现有窗口。
- 截图失败时弹出屏幕录制权限引导。
- 文件暂存区仅在拖拽文件期间发生快速横向方向变化后显示，避免普通拖拽误触。
- DMG 打开后可看到应用和 Applications 入口。

## Verification

- `cd OneBoard && swift build`
- `./script/build_app_bundle.sh`
- `./script/package_app.sh`
- `hdiutil imageinfo build/OneBoard.dmg`
