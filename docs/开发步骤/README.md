# OneBoard 开发步骤

## 2026-09-07 桌面浮窗可读性

日历与 Mac 状态使用随系统深浅色切换的不透明窗口底色，隔离桌面壁纸透色，并保留圆角、细边界及窗口阴影。日历非本月日期以次级文字和较轻字重区分，不对整格降低透明度；周数与 Mac 状态辅助信息提高可读性。改动仅作用于这两个浮窗，悬停、点击关闭和日历置顶行为保持原规则。

## 2026-09-07 文件拖动保持展开、刘海全域与权限精简

有效文件拖动期间暂存区自动展开并持续保持，松手后按鼠标位置恢复收起；不把旧 .drag 载荷或普通窗口拖动当成文件会话。刘海触发区使用系统实际刘海宽度，覆盖整个刘海及顶边，不向两侧扩张，底部仅保留 2pt 容差；普通悬停仍需连续 0.5 秒。暂存面板以顶部内凹肩线连接屏幕边缘，避免直角；展开收起仍保持不透明；原生窗口固定贴住屏幕顶边，仅内容从顶部中央缩放，并禁用系统默认窗口出场动画，避免叠加动画产生顶边闪缝。

文字与框选文字字号限制为 15–25，逐次加减 1，到边界停止；加减按钮整个 22×28pt 区域都可点击。文件拖动改为无权限轮询，移除输入监控监听、检测和设置入口，以及无实际 Finder Apple Events 调用的自动化声明。保留截图、选中文字/粘贴、提醒、用户目录授权等仍有用途的权限；卸载清理仍兼容历史授权记录。

## 2026-09-07 暂存接收与原位编辑回归

按最新要求移除暂存区右上角收起箭头，依靠移出自动收起。

FileShelfDropSessionTests 使用真实文件剪贴板调用 HostingView 的 AppKit 拖放回调，修改前接收失败，修复后接收成功；补半秒连续悬停、离开重置、关闭及 AirDrop 保持回归。文字测试覆盖单击选中、双击原位编辑、提交、取消与撤销；完成后安装固定证书包，实际操作 Finder 和截图进行验收。

## 2026-09-07 暂存拖放与标注视觉

先运行 FileDropTargetTests 复现原生接收区域未命中，再补转交。回归覆盖系统文件 URL 拖出与固定方格；ONEBOARD_STAGING_RENDER 可输出暂存与标注样式。完成后运行全量测试、Release 构建和固定开发证书 DMG 校验；Finder 实际拖放与动画观感另行验收。

## 2026-09-07 截图、账号与授权

先用序号删除回归复现断号，再实施修改。SeptemberInteractionRegressionTests 覆盖序号、OAuth 回调、目录解析、候选窗口、马赛克与暗罩。执行全量测试、深浅色离屏渲染、Release 构建及固定证书 DMG 验证。原生交互与账号登录单独标记验收状态。

详见[本轮修复记录](../修复记录/2026-09-07-截图账号与授权.md)。

## 2026-09-06 供应商与截图体验修订

本轮按复现、回归、实现、全量测试、离屏渲染、Release/DMG 验证执行。新增回归集中在 ProviderExperienceRegressionTests、ScreenshotExperienceRegressionTests、CloudSyncAndCalendarTests；ExperienceRenderTests 用 ONEBOARD_EXPERIENCE_RENDER 按需输出图。真实鼠标与系统权限流程需独立验收。

详见[本轮修复记录](../修复记录/2026-09-06-供应商与截图体验.md)。

## 2026-09-06 回归要求

额度测试覆盖 primary 为周窗口且无 secondary 的 Pro 用例；排序需验证重载后不变；快捷键绑定需验证取消选择不覆盖原值。

## 2026-09-06 长截图与刘海暂存回归修复

长截图四角引导、文字字号控件、Finder 两类 URL 载荷和刘海展开/收起几何由快速测试覆盖；安装后仍需从 Finder 向两个投放区各拖一次真实文件，确认暂存入库、AirDrop 收件人窗口，以及展开和反向缩回动画。

## 2026-09-06 快捷键与图标交互修订

回归覆盖旧绑定迁移不覆盖已占用键位、迁移幂等、图标同高以及运行时长跨日。执行 swift test --disable-sandbox；视觉渲染单独执行 FeaturePanelRenderTests，避免系统权限检查污染完整测试进程。手动检查模式切换、绑定弹层、取色及长截图遮罩。

## 2026-09-06 17:12 交互与文件类型修订

回归先检查 700ms 悬停与自定义扩展的失败测试，再执行全量 Swift 测试。视觉测试需填充三条应用网络数据，避免只验空状态。安装验收仍需真实 Finder 拖放/AirDrop 收件人界面、剪贴板单/双击及快速滚动；静态渲染不可替代系统交互验收。

## 2026-09-06 交互验收

MenuCalendarInteractionTests 覆盖真实面板标题栏/二次点击与悬停穿行状态；ManualCaptureAndFolderSyncTests 的稀疏文字滚动测试先失败后通过；MacStatusTests 检查实际内存、磁盘、CPU 区间与采样历史。FeaturePanelRenderTests 单独输出日历、状态、刘海深浅色。

安装后仍须真实验收：菜单栏悬停→移入卡片→移出、pin→切换应用、剪贴板双击→输入位置、长截图连续缓慢滚动→右侧增长→完成/AirDrop 接收方确认。CUA 在当前机器连接新版 app 路径超时，Bundle ID 因多个副本存在歧义，不能将自动测试称为完整真实交互验收。

## 2026-09-06 验收补充

运行全量 Swift 测试和 Release 构建。CalendarAndBackupRegressionTests 覆盖五年月份固定六行、2026 节假日/24 节气、明文备份往返与上一版、快捷键恢复。ClipboardPreviewTests 反复挂载文件预览再切换文本。视觉渲染测试单独执行，避免非 App 测试进程的异步通知授权检查。安装后人工验收手动滚动不闪边框、真实文件切换、iCloud 上传及重装恢复；本地备份测试不等同云端上传验证。

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

### 2026-09-04：供应商编辑页信息架构优化 ✅

1. ✅ 直接核对本地 CC Switch 源码，将编辑页拆分为基本信息、连接鉴权和 Claude 高级模型槽位
2. ✅ 增加供应商备注与官网链接，API Key 支持默认遮蔽、主动显隐和直接更新
3. ✅ 鉴权字段移入高级选项并补充 `AUTH_TOKEN` / `API_KEY` 选择说明
4. ✅ 供应商元数据和 API Key 继续只写 OneBoard SQLite，不接入钥匙串
5. ✅ 对齐角色表格、一键设置、默认兜底模型与独立 1M 开关

### 2026-09-04：CC Switch Codex / Claude 独立代理迁移 ✅

1. ✅ 固定 CC Switch MIT 源码提交，构建无界面 Rust sidecar 并随 OneBoard.app 打包
2. ✅ sidecar 使用内存数据库；供应商、代理元数据和 API Key 只由 OneBoard SQLite 持久化
3. ✅ 接入 Anthropic / OpenAI Chat / OpenAI Responses / Gemini Native 转换、SSE 与请求覆盖
4. ✅ 增加完整 URL、User-Agent、备用端点、测速择优、缓存路由和 Codex→Anthropic 选项
5. ✅ 客户端活动配置只写本地代理和 `PROXY_MANAGED`，保留稳定备份与原子写入
6. ✅ 请求级验证 Claude→Chat 与 Codex→Anthropic 双向转换、真实 Key 注入和覆盖规则

### 2026-09-04：Codex API Key 切换重载修复 ✅

1. ✅ 对照 CC Switch 当前供应商更新时同步 Live 配置的行为，补齐 OneBoard 活动供应商保存后的代理重载
2. ✅ Codex 运行中切换时先关闭并确认旧 app-server 退出，写入完成后自动重新打开
3. ✅ 编辑页增加“保存并切换”，区分仅保存非活动配置与立即启用
4. ✅ 增加正常重启、关闭失败回滚、重开失败保留新配置和活动 Key 更新回归测试

### 2026-09-04：Codex 自定义模型目录与配置简化 ✅

1. ✅ 自定义 Codex 供应商切换时生成 OneBoard 受管模型目录，并通过 `model_catalog_json` 让模型选择器展示当前供应商模型
2. ✅ 切回官方供应商时移除目录覆盖，恢复 Codex 内置模型列表
3. ✅ DeepSeek 地址自动选择 OpenAI Chat Completions；高级兼容设置和 Claude 模型槽位默认折叠
4. ✅ 增加配置合并、目录内容、官方恢复和 DeepSeek 协议推荐回归测试



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

## 2026-09-05 模型目录选择与额度说明

验证打开已保存供应商自动获取目录，六个模型槽位均可选择或手动输入；检查 1M 标记不丢失，更换地址/API Key 后旧列表清空。运行全量 swift test、Release 构建、正式打包及 hdiutil verify。

## 2026-09-05 第三方额度、Token 统计与翻译 Key 选择

- 额度：内置 DeepSeek、Sub2API、SiliconFlow、OpenRouter 查询。自动识别官方域名，其他同源地址尝试 Sub2API `/v1/usage`；可在编辑页选择额度接口类型。失败显示 HTTP 状态及服务端原因，旧快照标明时间；不执行导入脚本。
- 统计：按 API Key 和供应商源分组，展示当日、累计、缓存命中 Token，展开查看输入、输出和缓存写入。相同 Key 的 Codex/Claude 配置共享本地统计，换 Key 后分开计算。
- 数据源：Sub2API 有历史用量时展示供应商当日/累计快照；OneBoard 本地统计仅覆盖启用后通过内置代理或翻译的请求，按本机时区计算自然日，包含缓存 Token 且不重复相加，不与供应商统计合计。余额接口未返回 Token 时不推算历史 Token。
- 存储：代理复用 CC Switch 的响应解析，向 stdout 输出无正文、无 Key 的计数事件；主应用写入 oneboard.sqlite 的 ai_usage_events，按请求 ID 去重。Key 仍仅在 SQLite 和代理内存中；正常退出刷新尾部计数，异常强杀可能丢失尚未输出的短暂内存事件。
- 翻译：设置页选择默认 API Key；翻译窗口可临时切换具体供应商配置，复用其默认模型、连接及协议，支持 Chat Completions、Responses、Anthropic Messages 和 Gemini；不改变 Codex/Claude 活动配置，也不再单独填写 DeepSeek Key。

## 2026-09-05 设置页整体视觉升级

完成设置窗口及全部九类页面、供应商/网关/账号编辑弹窗的统一外观。生成九页浅色/深色预览，检查最小窗口尺寸、空状态、带用量供应商卡片和 OAuth/网关弹窗；临时截图测试不保留在常规测试集中。全量测试和 Release 打包后验证 DMG。

## 2026-09-05 导航与面板验收

1. 核对设置 11 个分类和菜单日常工具入口，旧持久化标识仍可解析；Finder 类型设置从待办移至文件页。
2. 运行 `swift test --disable-sandbox` 和 `swift build -c release --disable-sandbox`（在 OneBoard/）。导航回归验证快捷动作目标与维护菜单隔离。
3. 可设置 `ONEBOARD_RENDER_DIRECTORY=/tmp/oneboard-feature-review` 并运行 `swift test --disable-sandbox --filter FeaturePanelRenderTests`，输出独立面板和设置分类的深浅色、最小尺寸与内容状态图片；该测试默认跳过，演示数据仅放入测试进程内存。
4. 从根目录运行 `ONEBOARD_CODESIGN_IDENTITY=- bash script/package_app.sh`，并执行 `hdiutil verify build/OneBoard.dmg`。真实拖放、系统授权与菜单点击以开发包人工验收为准。

## 2026-09-05 截图验收

自动测试覆盖旧拖拽残留、新文件与同文件重新拖动、1px Retina 条纹导出和贴图渲染、实际贴图窗口尺寸、窗口层级命中、单击与自定义拖动、跨屏坐标及翻译回调。系统剪贴板测试需要可访问 pasteboard 服务的环境。运行全量测试、Release 构建、正式打包及 hdiutil verify。人工验收包含实际屏幕刚置顶清晰度、跨屏移动、窗口悬停、文件摇晃和真实翻译服务；测试图案通过不能代替用户现场的模糊问题确认。

### 窗口预选稳定性修正（2026-09-05）

窗口预选追加验证：testWindowPreviewRetainsOpaqueScreenshotPixels 检查预选区 alpha=1、背景原图内容及方向；testWindowPreviewSurvivesMouseDownAndSmallJitter 检查按下与抖动期间保留高亮。可设置 ONEBOARD_RENDER_DIRECTORY 并运行 ScreenshotSelectionTests/testWindowPreview 输出 window-hover.png。

### 2026-09-05 回归检查

运行 `swift test --disable-sandbox` 与 Release 构建；测试需要 macOS 屏幕/剪贴板服务，受限环境可能导致原有拖拽测试失败。`script/tests/test_ai_usage_proxy.py` 验证 Anthropic 普通/SSE计数；设置 `ONEBOARD_TEST_FORMAT=openai_chat` 验证带缓存 usage 的 Chat Completions 转换计数。代理测试使用本地假上游，不调用真实 Key。桌面测试覆盖菜单入口、符号链接目录与三种文件生成。最后正式打包并运行 `hdiutil verify build/OneBoard.dmg`。真实系统授权、指纹窗口焦点及 iCloud Finder 菜单仍需安装后交互验收。

### 2026-09-05 设置首次打开崩溃修复

构建后独立运行 python3 script/tests/test_settings_cold_start.py（Release 使用 ONEBOARD_TEST_CONFIGURATION=release），验证未预热单例的设置窗口打开、布局与再次打开；随后全量测试及正式打包、DMG 校验。

## 2026-09-06 验证清单

1. 运行 `CloudSyncAndCalendarTests`，验证偏好白名单、云端删除传播、额度缓存保留、日历周起始和长图拼接尺寸。
2. 在两个使用同一 iCloud 账号的正式签名安装包上修改普通偏好、AI Key 与账号配置，确认双向同步；关闭同步后确认本地数据不被删除。
3. 切换日历菜单栏开关，验证独立图标即时增删；检查周一/周日表头、月份切换与今天定位。
4. 在 Finder 文件夹空白处、所选文件和工具栏菜单分别打开终端，确认目录正确；iCloud Desktop 继续遵守 File Provider 限制。
5. 在浏览器/文档滚动区执行长截图，确认自动滚动、到底停止、拼接顺序、标注与保存；非滚动区应在画面不变时停止。
6. 分别验证系统、Google、自定义翻译；用假上游/测试 Key 验证模型目录、连接测试和错误呈现。
7. 从 `OneBoard/` 跑全量测试与 Release build，从仓库根目录打包并 `hdiutil verify build/OneBoard.dmg`。CloudKit、Finder、系统终端与真实滚动属于安装包人工验收。
8. 本地 DMG 默认使用 `OneBoard.local.entitlements`；从 DMG 内实际启动并确认进程驻留。只有准备好有效 iCloud provisioning profile 时才以 `ONEBOARD_ENABLE_ICLOUD_SYNC=1 script/package_app.sh` 构建 CloudKit 版本。
# 2026-09-06 验证补充

1. 用拖拽粘贴板夹具验证首帧展开、单次触发和旧文件不误触。
2. 验证应用/工具选择器、OCR AI 服务选择、菜单栏开关和日历选中态。
3. 全量运行 SwiftPM 测试、Release 构建、正式打包及 `hdiutil verify`，再进行截图和长截图实机验收。


## 2026-09-07 iCloud 授权与 Claude Code 账号

- 文件夹授权按规范化文件系统路径校验，忽略目录 URL 末尾斜杠；授权错误显示在对应行。选择后立即重试已开启的备份，异步读写期间保持安全作用域访问。
- 授权状态与操作统一样式，文件夹使用已连接状态、更改和断开操作。
- 新增独立 Claude Code 账号页，复用 AI 模型配置与 SQLite 授权，支持添加、切换、编辑、重新授权和删除；切换后新会话生效。
- 内置代理检测父进程存活；OneBoard 强退或崩溃后代理自行停止并释放端口，正常退出继续使用既有清理路径。

Claude Code 账号页不展示共享的供应商切换状态，避免串入 Codex 提示；仅显示本页操作错误。

Claude Code 授权页与 Codex 统一标题、待授权账号、OAuth 卡片、浏览器等待状态、链接复制及取消操作；按 Claude 授权流程保留授权码回填，账号输入位于弹窗内。

- Mac 状态磁盘总容量与空闲容量使用十进制（1 GB = 1,000,000,000 字节）；空闲不含系统可清理空间，内存仍使用二进制格式。
