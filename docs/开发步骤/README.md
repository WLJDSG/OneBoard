# OneBoard 开发步骤

## 项目概述

OneBoard 是一款 macOS 原生应用，整合三大功能：截图工具、历史剪贴板、文件暂存。

## 开发阶段

### 第一阶段：项目骨架 + 剪贴板模块 ✅

**状态：已完成**

1. 创建 Xcode/SPM 项目，添加依赖（GRDB、KeyboardShortcuts、LaunchAtLogin）
2. 实现 DatabaseManager + V1 迁移（clipboard_history 表 + FTS5）
3. 实现 AppDelegate（菜单栏图标 + Popover 壳）
4. 实现 HotkeyManager（剪贴板快捷键）
5. 实现 PasteboardMonitor（剪贴板轮询）
6. 实现 ClipboardRepository（CRUD + 搜索）
7. 构建 ClipboardPopoverView / ClipboardListView / ClipboardRowView
8. 实现置顶、删除、搜索、点击粘贴（CGEventPost 模拟 Cmd+V）
9. 实现保留策略（按条数 / 按天数）

### 第二阶段：截图模块 ✅

**状态：已完成（v1.0.20）**

1. ✅ 实现 ScreenshotCaptureService（纯 `screencapture -i` 系统工具，`Task.detached` 后台执行）
2. ✅ 实现 AnnotationService + AnnotationCanvasView（标注画布 + 实时拖动/绘制）
3. ✅ 构建 AnnotationToolbarView（矩形/椭圆/箭头/直线/文字/马赛克 + 预设色/RGB 颜色面板）
4. ✅ 实现 PinnedScreenshotWindow（置顶贴图浮动窗口）
5. ✅ 实现 AppleVisionOCRService + OCR 设置界面
6. ✅ 实现 TranslationService + DeepSeek AI 翻译
7. ✅ 添加第三方 API 配置入口（工厂模式）
8. ✅ 工具栏独立悬浮窗（level+1，MainActor.assumeIsolated 跟随）
9. ✅ 截图架构迭代完成（dlsym → CGWindowList → screencapture → 纯系统工具）

### 第三阶段：文件暂存模块 ✅

**状态：已完成（已修复非文件拖拽误触发）**

1. ✅ 实现 DragDetector（全局鼠标监控 + 文件拖拽摇动检测算法）

### 第七阶段：截图标注工具栏升级 ✅

**状态：已完成**

1. ✅ 扩展标注图层模型，新增编号标注（`.number`）
2. ✅ 实现撤销/重做历史（`redoLayers`、`canUndo`/`canRedo`）
3. ✅ 渲染编号标注（彩色圆形 + 数字文字）
4. ✅ 新增工具感知的样式控制（`presetColors`、`incrementStyleValue` 等）
5. ✅ 鼠标点击 + 键盘快捷键路由（数字键切换工具、Option 键颜色/样式）
6. ✅ 重构标注工具栏为四组：工具组 / 样式组 / 历史组 / 输出组
7. ✅ 桌面直存（一键保存 PNG 到 ~/Desktop）+ 画布像素尺寸显示

2. ✅ V2 迁移（staged_files 表，已在 Phase 1 创建）
3. ✅ 实现 DropZoneWindowController（右上角弹出、接受拖放、注册 NSDraggingDestination）
4. ✅ 实现 FileStagingRepository
5. ✅ 构建 FileShelfView / StagedFileRowView（浮动窗口、缩略图、拖出功能 onDrag）
6. ✅ 实现从书架拖出文件
7. ✅ 限制触发条件为新的文件拖拽会话，避免普通鼠标按住晃动唤出暂存区

### 第四阶段：收尾打磨 ✅

**状态：已完成（已生成 DMG）**

1. ✅ 设置窗口（通用、快捷键录制、关于）
2. ✅ 实现 LaunchAtLogin
3. ✅ 淡蓝色主题全局应用
4. ✅ 权限引导页面（首次启动检测辅助功能/屏幕录制权限）
5. ✅ 错误处理和边界情况
6. ✅ 创建 `.app` bundle 并打包 `build/OneBoard.dmg`
7. ⬜ 配置签名/公证（后续发布操作）

### 第五阶段：网关切换集成 ✅

**状态：已完成第一版实现**

1. ✅ 明确将独立 `gateway-switch` 完全并入 OneBoard
2. ✅ 确定第一版范围：网关/DNS Profile、专用切换小窗、可配置全局快捷键、OneBoard 专属免密 helper
3. ✅ 确定不迁移旧 `gateway-switch` 配置，不并入 Widget 和 URL Scheme
4. ✅ 设计独立“授权”设置页，统一管理辅助功能、屏幕录制、网关 helper、开机自启
5. ✅ 设计 `清除 OneBoard 授权...` 弹窗，支持仅清隐私权限或清除全部授权
6. ✅ 实施 `OneBoard/Modules/Gateway/` 模块
7. ✅ 实施设置页、菜单入口、小窗和快捷键
8. ✅ 修复权限开关和文案状态联动
9. ✅ 迁移/补充网关相关测试并通过 `swift build`

### 第六阶段：截图、权限与剪贴板体验修整 ✅

**状态：已完成实现，DMG 生成受当前沙盒环境限制**

1. ✅ 修复点击剪贴板历史条目粘贴时重复生成记录的问题
2. ✅ 优化截图工具栏，移除复制按钮，新增完成按钮（复制截图并关闭）
3. ✅ 扩展截图标注预设颜色，并按工具、颜色、动作分组
4. ✅ 修复连续截图导致旧截图窗口/工具栏残留的问题
5. ✅ 新增 OCR 识别结果气泡弹窗，支持编辑、复制和外部点击关闭
6. ✅ 优化翻译工作台布局，压缩头部留白并固定窗口完整尺寸
7. ✅ 优化权限页单项关闭后的状态刷新和文案
8. ✅ 打包脚本新增 LaunchAtLogin helper 与主 App 的 ad-hoc 签名和验证输出
9. ⚠️ `script/package_app.sh` 已完成构建和签名验证，但当前沙盒内 `hdiutil create` 报“设备未配置”，未能在本轮生成新的 DMG



### 第八阶段：截图模块深度优化 ✅

**状态：已完成（2026-06-15）**

1. ✅ 粗细循环调整：`incrementStyleValue`/`decrementStyleValue` 到达边界后 wrap 回另一端
2. ✅ 修复贴字漂移 bug：渲染管线重构，文字标注直接算像素坐标，消除双重 Y 翻转导致的坐标偏移
3. ✅ 自定义全屏遮罩截图：`ScreenshotOverlayView` 替换系统 `screencapture -i`
   - 半透明暗色遮罩 + 框选区域挖空显示原图
   - `screencapture -x` 后台线程静默全屏截图
   - 修复 `NSImage.draw` 触发 `NSCoreDragCapture → SIGABRT` 闪退，改用 `CGContext.draw`
4. ✅ 像素尺寸预览：选区右上角实时显示 W×H 蓝色标签
5. ✅ 方向键微调选区：方向键 1px 调整，Shift+方向键 10px 步进
6. ✅ 智能窗口截图：鼠标悬浮自动高亮窗口轮廓（`CGWindowListCopyWindowInfo`），单击直接截取整窗
7. ✅ OCR 弹窗弹性尺寸：根据文字内容自适应高度（200~520pt），智能定位优先下方→上方→右侧→左侧
8. ✅ 贴字 UI 微信风格重做：
   - 打字时虚线框 + 无背景，字体跟随工具栏 ± 按钮
   - 缩放手柄改为 6px 彩色圆点
   - 编辑弹窗 `ultraThinMaterial` + 阴影
   - 漂移 bug 修复（见第 2 项）

## 验证方案

每阶段完成后，通过以下方式进行验证：

1. **剪贴板模块**：复制不同类型的文本/图片/文件，确认在 Popover 中正确显示，测试搜索/置顶/删除/点击粘贴
2. **截图模块**：按下截图快捷键，框选区域，使用各种标注工具，测试 OCR 识别和翻译，测试贴图置顶
3. **文件暂存**：在 Finder 中拖拽文件并晃动，确认右上角弹出暂存区；普通鼠标按住晃动不应触发暂存区；放入文件后切换应用，测试拖出文件发送
4. **全局快捷键**：在不同应用中使用快捷键，确认功能正常触发
5. **开机自启**：重启电脑确认应用自动启动
6. **权限**：首次启动确认权限引导页正常显示，引导用户开启所需权限
7. **打包产物**：执行 `script/package_app.sh` 生成 `build/OneBoard.dmg`，并通过 `hdiutil verify build/OneBoard.dmg` 校验镜像
8. **网关模块**：切换当前默认路由所在服务的网关/DNS，验证 Wi-Fi/有线网络自动识别、仅 DNS 模式、helper 安装/卸载和授权状态同步
