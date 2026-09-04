# OneBoard 开发步骤

## 项目概述

OneBoard 是一款 macOS 原生应用，整合截图工具、历史剪贴板、文件暂存、Finder 快速新建、网关切换、AI 模型供应商切换、Codex 桌面账号切换和待办事项。

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

1. ✅ 实现 ScreenshotCaptureService（按显示器执行 `screencapture -D`，`Task.detached` 后台捕获，每块屏幕独立遮罩与裁剪）
2. ✅ 实现 AnnotationService + AnnotationCanvasView（标注画布 + 实时拖动/绘制）
3. ✅ 构建 AnnotationToolbarView（矩形/椭圆/箭头/直线/文字/马赛克 + 预设色/RGB 颜色面板）
4. ✅ 实现 PinnedScreenshotWindow（置顶贴图浮动窗口）
5. ✅ 实现 AppleVisionOCRService + OCR 设置界面
6. ✅ 实现 TranslationService + DeepSeek AI 翻译
7. ✅ 添加第三方 API 配置入口（工厂模式）
8. ✅ 完整工具栏内嵌遮罩并在调整/标注阶段复用，输出动作统一经过截图会话生命周期
9. ✅ 截图架构迭代完成（dlsym → CGWindowList → screencapture → 多显示器独立捕获与原位画布）

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
10. ✅ Helper v3 安装时原子写入初始 IPv4 白名单，业务拒绝不再回退到管理员密码命令
11. ✅ Helper v4 为网关切换和卸载接入 Touch ID/登录密码身份确认，移除 Helper 缺失时的管理员 shell 回退，并增加受限自卸载命令

### 第六阶段：截图、权限与剪贴板体验修整 ✅

**状态：已完成；后续正式打包与 DMG 校验已通过**

1. ✅ 修复点击剪贴板历史条目粘贴时重复生成记录的问题
2. ✅ 优化截图工具栏，移除复制按钮，新增完成按钮（复制截图并关闭）
3. ✅ 扩展截图标注预设颜色，并按工具、颜色、动作分组
4. ✅ 修复连续截图导致旧截图窗口/工具栏残留的问题
5. ✅ 新增 OCR 识别结果气泡弹窗，支持编辑、复制和外部点击关闭
6. ✅ 优化翻译工作台布局，压缩头部留白并固定窗口完整尺寸
7. ✅ 优化权限页单项关闭后的状态刷新和文案
8. ✅ 打包脚本新增 LaunchAtLogin helper 与主 App 的 ad-hoc 签名和验证输出
9. ✅ 后续已使用标准脚本完成 Release 构建、签名、DMG 生成和 `hdiutil verify`

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

**状态：已完成，并于 2026-07-13 完成 macOS 26 权限链路修复**

1. ✅ Finder Sync Extension（FIFinderSync 协议）
2. ✅ 右键受支持的本地文件夹/本地桌面空白 → “新建文件”子菜单（txt/docx/xlsx）
3. ✅ 通过 `oneboard://new-file` 将写入请求交给主应用，避免扩展沙盒直接写入失败
4. ✅ 自动命名、冲突处理，并在 Finder 中选中新文件
5. ✅ 根目录、用户目录、本地 Desktop、系统解析 Desktop 及符号链接目标监听；桌面空白处回退到真实 `~/Desktop`
6. ✅ `build_app_bundle.sh` 编译、打包并签名 `.appex`
7. ✅ Cmd+Q 修复（`setupHiddenMainMenu`，仅应用活跃时响应）
8. ✅ 授权设置页新增 Finder 扩展启用提示

### 2026-07-13：macOS 26 交互兼容修复 ✅

**状态：已完成并生成验证通过的 DMG（2026-07-13）**

1. ✅ 摇晃检测在缺少输入监听权限时保留轮询降级通道
2. ✅ Finder 快速新建覆盖桌面及任意受监控目录，并改由主应用执行写入
3. ✅ Retina 截图按框选区域逻辑尺寸原位显示
4. ✅ 网关切换弹窗缩小为 330×300，并移除异常外边框
5. ✅ 新增 Finder 请求、文件创建、截图布局、摇晃启动策略和网关布局回归测试
6. ✅ 全量 65 项测试、Release 构建、签名、DMG checksum 和新建文件端到端验证通过

### 2026-07-14：截图选区调整与文件暂存类型收紧 ✅

**状态：已完成并生成验证通过的 DMG（2026-07-14）**

1. ✅ 修复截图屏幕坐标重复翻转：CGImage 裁剪继续翻转 Y，AppKit 原位显示不再翻转 Y
2. ✅ 鼠标松开后保留选区，支持内部拖动和四边、四角共八方向缩放
3. ✅ 新增选区阶段工具栏；点击任意标注工具后立即锁定，锁定后不可调整截图范围
4. ✅ 复制、保存、贴图、OCR、翻译统一使用锁定后的区域
5. ✅ 文件暂存只读取真实普通文件 URL，拒绝应用窗口、目录和 `.app` 应用包
6. ✅ 新增坐标映射、选区几何、一次性锁定、工具路由和普通文件过滤回归测试
7. ✅ 全量 78 项测试、Release 构建、ad-hoc 签名、DMG 生成与 checksum 验证通过

### 2026-07-17：多显示器截图、统一工具栏、Finder 与网关边界修复 ✅

**状态：已完成并生成验证通过的 DMG（2026-07-17）**

1. ✅ 每块显示器独立执行 `screencapture -D`，创建对应遮罩，并从鼠标所在屏幕开始交互
2. ✅ 选区调整和标注阶段复用完整 `AnnotationToolbarView`，删除第二套精简工具栏
3. ✅ 标注工具点击后立即锁定并安装画布，画布切换时转交第一次鼠标按下，避免首笔丢失
4. ✅ OCR 等输出动作统一返回截图会话，关闭所有遮罩后再显示结果
5. ✅ Finder 桌面监听和 entitlement 覆盖本地 Desktop、系统解析目录及符号链接目标；File Provider 管理的 iCloud 桌面不在 Finder Sync 支持范围内
6. ✅ 网关 Helper 升级为 v3，安装与初始白名单写入只需一次授权，白名单拒绝不再进入管理员命令回退
7. ✅ 全量 88 项 XCTest 通过，新增多屏捕获计划、标注锁定/画布、OCR 会话、Finder entitlement 和网关回退边界测试

### 2026-08-31：Codex 桌面多账号切换 ✅

**状态：实现、全量测试、Release 构建和 DMG 校验均已完成**

1. ✅ 新增 Codex 账号模型、SQLite 元数据仓库和认证缓存 vault
2. ✅ 只接管官方浏览器登录完成后的认证缓存，不保存账号密码或验证码
3. ✅ 新增切换状态机：Codex 运行中不改凭据，确认进程消失后再提交切换
4. ✅ 切换前保存当前账号可能已刷新的缓存，原子恢复目标缓存并保持 `0600` 文件权限
5. ✅ 设置页新增 Codex 账号 tab，支持保存当前登录、更新、重命名、删除和切换
6. ✅ 菜单栏新增 Codex 账号快捷子菜单，显示当前与切换中状态
7. ✅ 彻底卸载通过删除 OneBoard Application Support 目录清理 SQLite 凭据
8. ✅ 新增隔离临时文件的服务与编辑器测试，不读取用户真实认证缓存

### 2026-09-02：Codex 自动进程切换与官方存储兼容 ✅

1. ✅ 参考 cockpit-tools 的事务顺序：校验目标、退出进程、提交凭据、重新启动
2. ✅ 退出前捕获直属 Codex app-server，防止旧 token 在切换后回写
3. ✅ 强制 `cli_auth_credentials_store = "file"`，彻底移除 OneBoard 与 Codex 官方钥匙串依赖
4. ✅ 设置页保持 grouped Form 风格，切换期间显示进度并禁用并发操作

### 2026-09-03：Codex OAuth 新增账号 ✅

1. ✅ 接入 Codex CLI 标准形态的 authorization-code + PKCE 授权链接，直接打开 OpenAI 授权端点
2. ✅ 监听官方登记的 `http://localhost:1455/auth/callback`，校验 `state` 后交换令牌
3. ✅ 授权成功后生成 Codex 官方认证结构并保存到 OneBoard SQLite vault
4. ✅ 设置页改为“填写邮箱 → 浏览器授权 → 自动入库”，保留重命名、删除和快速切换
5. ✅ 修复 Codex Desktop 私有中转页注入工作区参数后返回 `invalid_authorize_request`，移除 Desktop 专用版本和稳定 ID 参数
6. ✅ Google 免费翻译端点返回 429/HTML 时改为可操作中文提示，并补确定性网络回归测试
7. ✅ 账号行新增 5 小时/每周剩余额度、重置时间、订阅到期和剩余主动重置次数
8. ✅ App 启动后每 15 分钟自动更新账号状态，access token 到期或远端拒绝时自动续期并保存 refresh token 轮换结果
9. ✅ 当前账号正在 Codex 中运行时暂缓 OneBoard 侧凭据轮换；切号前自动续期目标账号且仍在关闭 Codex 前完成校验
10. ✅ 新增额度响应换算、订阅解析、主动重置次数、凭据轮换和运行中互斥回归测试

### 2026-09-03：Codex / Claude Code 模型供应商切换 ✅

1. ✅ 对照 cc-switch 的 Codex TOML 和 Claude settings JSON 投影规则，建立独立 `AIModels` 模块
2. ✅ 新增供应商元数据仓库与 SQLite API Key vault，官方/自定义 API 分开验证
3. ✅ Codex 保留未知 TOML 字段并管理 OneBoard 专用 provider 表，不改动账号 `auth.json`
4. ✅ Claude Code 保留 settings JSON 其他字段，合并更新 API 与 Haiku/Sonnet/Opus 默认模型键
5. ✅ 配置文件原子写入、`0600` 权限、符号链接拦截和首次切换备份/恢复
6. ✅ 设置页新增“AI 模型”页，菜单栏新增 Codex / Claude Code 两级快速切换
7. ✅ 新增配置合并、密钥字段、备份恢复、符号链接和独立活动状态回归测试
8. ✅ 对齐 CC Switch 新版 Claude 槽位：补齐 Fable、角色显示名、子代理模型与 `[1M]` 配置说明
9. ✅ AI 模型列表复用官方 Codex 账号额度快照并提供刷新；第三方无查询契约时明确降级



### 第八阶段：截图模块深度优化 ✅

**状态：已完成（2026-06-15）**

1. ✅ 粗细循环调整：`incrementStyleValue`/`decrementStyleValue` 到达边界后 wrap 回另一端
2. ✅ 修复贴字漂移 bug：渲染管线重构，文字标注直接算像素坐标，消除双重 Y 翻转导致的坐标偏移
3. ✅ 自定义全屏遮罩截图：`ScreenshotOverlayView` 替换系统 `screencapture -i`
   - 半透明暗色遮罩 + 框选区域挖空显示原图
   - `screencapture -D` 后台线程按显示器静默截图
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
2. **截图模块**：在主屏和外接屏分别于顶部、中央、底部框选；松开后移动并测试八方向缩放；点击工具后确认立即锁定、首笔生效且原位进入标注，再确认 OCR/翻译前所有遮罩已关闭
3. **文件暂存**：在 Finder 中分别拖拽文本、图片和压缩包并晃动；确认应用窗口、目录和 `.app` 不触发暂存区，也不能被加入暂存列表
4. **全局快捷键**：在不同应用中使用快捷键，确认功能正常触发
5. **开机自启**：重启电脑确认应用自动启动
6. **权限**：首次启动确认权限引导页正常显示，引导用户开启所需权限
7. **打包产物**：执行 `script/package_app.sh` 生成 `build/OneBoard.dmg`，并通过 `hdiutil verify build/OneBoard.dmg` 校验镜像
8. **网关模块**：切换当前默认路由所在服务的网关/DNS，验证 Wi-Fi/有线网络自动识别、仅 DNS 模式、Helper 安装/卸载和授权状态同步；切换与卸载优先弹 Touch ID、无指纹时回退登录密码，首次安装/升级只出现一次系统管理员授权；Helper 缺失或地址未进白名单时必须直接失败且不得弹管理员 shell
9. **待办模块**：选中文字 + 快捷键添加待办，右键 Services 菜单添加，鼠标移至顶部中央刘海触发面板，勾选完成淡出，查看历史统计，配置保留天数
10. **Finder 扩展**：分别在受支持的本地目录、本地 Desktop 和符号链接桌面右键 → “新建文件” → 创建 txt/docx/xlsx；确认请求由主应用处理、重名自动递增，且文件在 Finder 中被选中。启用 iCloud 同步的桌面应显示限制说明，不以出现 Finder Sync 菜单作为验收项
11. **Cmd+Q**：OneBoard 活跃时（设置窗口/浮动面板）Cmd+Q 退出；其他应用活跃时 Cmd+Q 不影响 OneBoard
12. **Codex 账号切换**：用两个真实测试账号分别在官方网页完成登录与验证码；保存后从设置页和菜单栏发起切换，确认 OneBoard 自动退出 Codex、退出期间不修改认证存储、切换后自动重开并进入目标账号，并验证 file 模式、SQLite 凭据、重命名、删除和彻底卸载清理
