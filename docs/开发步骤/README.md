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
9. ⚠️ `script/package_app.sh` 已完成构建和签名验证，但当前沙盒内 `hdiutil create` 报”设备未配置”，未能在本轮生成新的 DMG

### 第七阶段：待办事项模块 ✅

**状态：已完成实现**

1. ✅ V3 数据库迁移（todos 表 + FTS5 全文搜索）
2. ✅ TodoItem 模型 + Priority 枚举 + TodoRepository（CRUD + 统计查询）
3. ✅ TodoSlidePanelWindowManager（刘海触发 + 滑入/滑出动画 + 自动收起）
4. ✅ TodoSlidePanelView + TodoRowView（勾选框、优先级色标、截止日期、来源应用）
5. ✅ 全局快捷键（Cmd+Option+T 切换面板、Cmd+Shift+Option+T 添加选中文字）
6. ✅ 系统服务菜单（NSServices 注册，”添加到待办”出现在右键 Services 菜单）
7. ✅ 完成动画（勾选后 3 秒淡出 → 移入历史）
8. ✅ TodoHistoryView + TodoHistoryViewModel（每日柱状图、来源应用统计、完成率）
9. ✅ TodoReminderService（UNUserNotificationCenter 截止日期提醒 + 启动时过期待办通知）
10. ✅ 通知权限管理（SystemCapabilityViewModel + PermissionManager 扩展）
11. ✅ TodoSettingsView（保留天数、自动收起延迟、通知开关、Finder 文件类型管理）
12. ✅ 菜单栏”待办列表...”入口

### 第八阶段：Finder 新建文件 + Cmd+Q 修复 ✅

**状态：已完成实现**

1. ✅ Finder Sync Extension（独立 SPM target + FIFinderSync 协议）
2. ✅ 右键文件夹/桌面空白 → “新建文件”子菜单（txt/docx/xlsx/文件夹）
3. ✅ 文件创建逻辑（自动命名、冲突处理、Finder 中选中进入重命名）
4. ✅ App Group 共享 UserDefaults（主应用设置页管理文件类型，扩展读取配置）
5. ✅ build_app_bundle.sh 扩展编译 + .appex 打包 + 签名
6. ✅ Cmd+Q 修复（setupHiddenMainMenu，仅应用活跃时响应）
7. ✅ 主应用 entitlements 新增 app-group 权限
8. ✅ 授权设置页新增 Finder 扩展启用提示

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
9. **待办模块**：选中文字 + 快捷键添加待办，右键 Services 菜单添加，鼠标移至顶部中央刘海触发面板，勾选完成淡出，查看历史统计，配置保留天数
10. **Finder 扩展**：右键文件夹 → "新建文件"菜单 → 创建 txt/docx/xlsx/文件夹，文件在 Finder 中选中可重命名，设置页管理文件类型
11. **Cmd+Q**：OneBoard 活跃时（设置窗口/浮动面板）Cmd+Q 退出；其他应用活跃时 Cmd+Q 不影响 OneBoard
