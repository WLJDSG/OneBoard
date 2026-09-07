# OneBoard 打包与修复流程

本文档记录 OneBoard 的标准打包方法，以及以后修复 bug 时必须遵循的闭环流程。

## 打包产物

- 标准安装包只交付 `build/OneBoard.dmg`
- DMG 内应包含 `OneBoard.app` 和 `Applications` 软链接
- 不额外交付 `.app`、`.pkg`、zip 或其他安装产物，除非用户明确要求

## 标准打包命令

在仓库根目录执行：

```bash
script/package_app.sh
```

脚本会自动完成：

1. 执行 `script/build_app_bundle.sh`
2. 使用 SwiftPM 编译 Release 版本
3. 生成 `build/OneBoard.app`
4. 放入 LaunchAtLogin helper
5. 对 helper 和主 App 签名
6. 校验 app bundle 签名
7. 生成 `build/OneBoard.dmg`

## 签名身份

默认情况下，脚本会尝试查找可用的 `Developer ID Application` 或 `Apple Development` 签名身份。

日常安装测试使用同一本机开发证书；证书不可用时先解决签名问题，不降级为 ad-hoc 安装包。仅用于不安装的临时构建时，可以显式使用 ad-hoc 签名：

```bash
ONEBOARD_CODESIGN_IDENTITY=- script/package_app.sh
```

在 Codex 沙盒环境里，如果 `hdiutil create` 报“设备未配置”，需要在获得用户许可后在沙盒外执行同一个打包命令。不要绕过脚本手工拼装 DMG。

## 打包后验证

打包前先从 `OneBoard/` 目录执行全量测试和 Release 构建：

```bash
cd OneBoard
swift test --disable-sandbox
swift build -c release --disable-sandbox
cd ..
```

打包完成后必须验证 DMG：

```bash
hdiutil verify build/OneBoard.dmg
```

看到类似以下结果才算安装包有效：

```text
hdiutil: verify: checksum of "build/OneBoard.dmg" is VALID
```

可选检查产物大小：

```bash
ls -lh build/OneBoard.dmg
```

涉及 Finder 扩展或跨进程功能时，还必须挂载最终 DMG 检查真实产物，不能只检查打包过程中短暂存在的 `build/OneBoard.app`：

```bash
hdiutil attach -readonly -nobrowse build/OneBoard.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/OneBoard/OneBoard.app
test -x /Volumes/OneBoard/OneBoard.app/Contents/PlugIns/OneBoardFinderSync.appex/Contents/MacOS/OneBoardFinderSync
```

Finder 新建文件链路可在临时目录做端到端验证：启动 DMG 内 App 后，打开 `oneboard://new-file` URL，确认目标目录出现 `未命名.txt`。测试目录必须使用临时路径，不要污染用户桌面或文档目录。

## 修 bug 标准流程

每次修 bug 都必须按以下闭环执行：

1. **确定范围**：先明确 bug 影响的功能、入口、模块和复现条件，不扩大到无关重构。
2. **查清原因**：阅读相关需求、技术规范和代码；用日志、构建错误、复现结果或代码路径说明 bug 为什么发生。
3. **最小修复**：只修改必要文件，优先沿用现有架构和代码风格，避免顺手重构。
4. **验证修复**：先让针对真实症状的回归测试失败，再修复并运行定向测试、全量 `swift test` 和 Release 构建。
5. **未修复则继续**：如果验证失败，回到原因分析，继续修复和验证，直到确认修复为止。
6. **重新打包**：确认 bug 修复后，重新执行标准打包命令生成 `build/OneBoard.dmg`。
7. **验证安装包**：执行 `hdiutil verify build/OneBoard.dmg`，确认 DMG 有效。
8. **记录结果**：在开发日志中记录修复范围、根因、改动、测试数量、验证命令、DMG checksum 和无法自动完成的肉眼验收项。

涉及真实 macOS 手势的修复还必须列出人工验收项。例如截图框选需要验证顶部/中央/底部位置、移动、八方向缩放和标注后锁定；文件暂存需要验证普通文件可触发，而应用窗口、目录和 `.app` 不触发。自动化测试只能证明坐标与状态逻辑，不能代替真实鼠标手势验收。

涉及本轮系统集成功能时，还必须补充以下验收：

- **多显示器截图**：主屏、左右或上下排列的外接屏分别框选；混合 Retina/非 Retina 环境下，遮罩、裁剪、工具栏和标注方向必须落在同一块屏幕且比例一致。
- **截图会话**：点击每类标注工具都应立即锁定并接受第一笔；点击 OCR/翻译后所有屏幕遮罩必须先消失，结果窗口不能被遮挡。
- **Finder 桌面**：在受支持的本地 Desktop 和符号链接桌面验证右键菜单与主应用创建链路；启用 iCloud 同步的桌面只验证应用正确显示 Finder Sync 平台限制，不要求菜单出现。
- **网关 Helper**：首次安装与初始白名单写入只能出现一次管理员授权；未进白名单的 Router/DNS 必须直接失败，且不得弹出管理员授权绕过限制。

## 系统权限与截图专项规则

### 权限退出重启

- 不要只依赖 `applicationShouldTerminate` 返回 `.terminateNow`，这只能保证退出不被拦截，不能保证菜单栏 App 会被系统重新打开。
- 只有录屏授权引导仍处于活跃状态时，才允许安排延迟重启；普通 Cmd+Q 不应自动重启。
- 重启进程必须独立于当前 App，并在旧进程退出后执行 `open -n`。

### TCC 与彻底卸载

- `tccutil reset` 必须在删除 `.app` 之前执行，确保系统仍能解析 Bundle ID 与代码签名。
- `Accessibility` 必须对主 Bundle ID 单独执行并检查退出码，不能只依赖被静默忽略的批量循环。
- 不得使用无 Bundle ID 的全局 `tccutil reset Accessibility`，避免清除其他应用的辅助功能权限。
- App 内延迟卸载、仓库 `script/uninstall.sh` 和 DMG 内卸载入口必须保持相同清理顺序。
- Codex 多账号与 AI Provider 凭据统一保存在 `~/Library/Application Support/OneBoard/oneboard.sqlite`；彻底卸载删除整个 OneBoard Application Support 目录即可同步清理。

### 截图标注坐标

- 框选和标注必须在同一个遮罩会话内完成；禁止通过新增独立图片窗口模拟“在原区域标注”。
- 完整工具栏应作为遮罩窗口子视图显示在画布上层，不再维护第二套精简截图工具栏。
- 从 AppKit 事件映射到 SwiftUI 画布时必须读取目标 `NSView.isFlipped`：flipped 视图直接使用转换后的 Y，非 flipped 视图才执行 `bounds.height - y`。
- 回归测试必须实例化真实 `NSHostingView` 验证 flipped 属性，并断言鼠标 X/Y 位移与标注端点增量同向。

### 多显示器与输出生命周期

- 每块屏幕必须独立捕获、独立遮罩、独立裁剪，禁止用主屏坐标或像素比例解释外接屏图像。
- 任一屏幕完成或取消后必须统一清理全部遮罩和事件监听，避免另一块屏幕残留全屏覆盖层。
- 调整与标注阶段只允许维护一套完整工具栏；删除的精简工具栏不得重新引入。
- OCR、翻译、复制、保存和贴图必须通过截图会话完成回调，不能由工具栏直接创建后续窗口。

### Finder 与网关权限边界

- Finder 监听目录、符号链接解析和 Extension entitlement 必须一起修改、一起测试；Extension 只传请求，写文件仍由主应用执行。
- 网关 Helper 协议升级时必须同步版本标记、安装脚本、白名单初始化、回归测试和开发文档。
- 白名单拒绝是安全边界，不属于“Helper 不可用”；任何回退机制都不得绕过该拒绝。

## Codex 执行要求

以后 Codex 处理本项目 bug 或打包请求时，必须先阅读：

- `AGENTS.md`
- `docs/打包与修复流程/README.md`
- 与本次修改相关的需求、技术或设计文档

涉及代码修改时，必须在最终回复中说明：

- bug 范围
- 根因
- 最小修复内容
- 验证结果
- 新安装包路径

## 2026-09-07 权限身份稳定性

日常测试安装使用 `bash script/package_app.sh` 自动选择同一本机开发证书。ad-hoc 仅用于不安装的临时构建；不同构建的临时代码身份可能导致系统重新授权，不能作为稳定权限验收包。签名变更后的首次系统授权与同一包重复启动分开验收。
