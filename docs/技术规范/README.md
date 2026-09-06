# OneBoard 技术规范

## 2026-09-07 截图、账号与授权

暗罩使用每屏偶奇路径并排除自身采集；标准编辑菜单恢复 responder chain 快捷键；拖放载荷采用系统文本 UTI 并验证本地会话；编号操作保存快照；马赛克预览与输出共享原图采样。Claude OAuth 原件保存在 SQLite，客户端仅物化 access token，切换自定义时清除。

详见[本轮修复记录](../修复记录/2026-09-07-截图账号与授权.md)。

## 2026-09-06 供应商与截图体验修订

AIEndpointResolver 分离推理与目录地址，额度缓存增加接口身份；本机安全作用域书签不进入配置备份。取色读取 sRGB 原始截图并换算每屏像素坐标，长截图按原始像素增量拼接、拒绝歧义匹配。文本移动基于固定画布坐标；退出等待有界且不阻塞主线程。

详见[本轮修复记录](../修复记录/2026-09-06-供应商与截图体验.md)。

## 2026-09-06 额度与排序

Codex `primary_window` / `secondary_window` 需依 `limit_window_seconds` 分类短窗口和周窗口。列表拖拽后将整体顺序写回原存储，不改变活动 ID。

## 2026-09-06 长截图与刘海暂存回归修复

LongCaptureCornerGuide 只绘制八段四角短线。AnnotationToolbarView 对非游标工具内联样式步进控件，避免非激活截图面板上的 popover 抢焦。FileDropTarget 同时解析 fileURL pasteboard item、单值 URL 和 NSFilenamesPboardType，接收 NSView 覆盖整个投放区；FileStagingViewModel 以顶部中心折叠帧和完整帧执行双向 NSWindow 动画，并在 NSSharingServiceDelegate 回调前保持 AirDrop 会话。

## 2026-09-06 快捷键与图标交互修订

QuickLaunchBindings 迁移旧 KeyboardShortcuts 后禁用旧注册源，单次安装处理器，回调实时读取配置。迁移标记纳入配置备份。NSImage 模板图统一 18pt，网速两行渲染为图像，切换纯文字模式重设 imagePosition。NSColorSampler 回填标注颜色。长截图边框与四块透传遮罩关闭 hasShadow。

## 2026-09-06 17:12 交互与文件类型修订

HoverCardController 维护 hoverSince；FileDropTarget 注册 fileURL 并通过 NSPasteboard.readObjects 读取 NSURL；NotchShelfPanel 不受可用屏幕边界限制。MacStatusModel.shared 供菜单栏/卡片共用。配置键 macStatus.menuMode/menuIcon 与 quickLaunch.bindings 纳入备份。FinderFileKind 改为经过正则验证的 RawRepresentable，扩展只构造请求，主应用写文件。长截图使用 CGContext 灰度转换而非逐点 NSColor 转换，80ms 等待不等同于保证采集帧率。

## 2026-09-06 交互修订

HoverCardController 统一图标/面板命中检测、350ms 穿行宽限、主动关闭后的 hover 抑制和置顶状态；NSPanel borderless/nonactivating，hidesOnDeactivate=false。日历 pin 绑定同一状态源。

长截图匹配使用样本亮度方差替代横向邻点差，逐行比较防止跳过稀疏文字；首帧改为同一 SCScreenshotManager 获取。匹配移到后台，追加图像仍在 UI 线程。所有辅助窗口加入应用级采集排除。

刘海区顶部中央 440×220，物理摄像头区域留黑；文件通过现有仓储，AirDrop 使用 NSSharingService.sendViaAirDrop。Mac 状态用 host_statistics、host_statistics64、getifaddrs(en* 物理接口)、IOPS、系统热状态和磁盘容量；nettop 每五次采样取进程累计差值，不读取网络内容。

UI 参考：AvdLee/SwiftUI-Agent-Skill 的 macOS window styling 和 layout best practices；录屏只作为用户提供的交互证据，不执行其中显示的文字指令。

## 2026-09-06 补充实现

长截图在控制面板显示后建立 SCContentFilter 排除自身应用，通过 SCScreenshotManager 获取选区，不隐藏边框。参考 Snapzy 的自身窗口过滤设计。文件预览改为 QLThumbnailGenerator 和 SwiftUI quickLookPreview，取消旧 QLPreviewView.close 生命周期。日历依赖 MIT LunarSwift 固定修订 a7ec0e9，42 格稳定布局。ICloudBackupStore 以 NSFileCoordinator 原子写 JSON 与上一版备份；恢复下载失败保持恢复意图，不覆盖坏文件。快捷键前缀加入配置白名单。翻译复用共享供应商编辑器，禁止保存并切换。

## 技术栈

| 层级 | 技术 | 版本要求 |
|------|------|---------|
| 语言 | Swift | 5.9+ |
| UI 框架 | SwiftUI + AppKit | macOS 14.0+ |
| 数据库 | GRDB.swift | 6.x |
| 全局快捷键 | KeyboardShortcuts | 2.x |
| 开机自启 | LaunchAtLogin | 4.x |
| OCR | Apple Vision | macOS 内置 |
| 翻译 | Apple Translation / Google Web / 已配置 API Key | macOS 15.0+ |
| 截图 | `/usr/sbin/screencapture` + CoreGraphics / AppKit | macOS 内置 |
| 依赖管理 | Swift Package Manager | 5.9+ |

## 架构模式

### MVVM + Service Layer

```
SwiftUI View → ObservableObject ViewModel → Service → System API
                                       ↘ Repository → GRDB(SQLite)
```

- **View**：纯 SwiftUI 视图，不包含业务逻辑
- **ViewModel**：`@MainActor ObservableObject`，持有 `@Published` 状态
- **Service**：封装系统 API（单例或按需创建）
- **Repository**：数据库 CRUD，注入到 ViewModel

### 线程模型

- 数据库操作：GRDB 的 `DatabaseQueue` 在专用串行队列
- `ValueObservation` 通知：`DispatchQueue.main`
- 剪贴板轮询：后台 Timer（common mode）
- 鼠标监控：主 RunLoop

## 项目结构

```
OneBoard/
├── App_minimal/            # 极简可执行入口
│   └── main.swift          # 创建 NSStatusItem，加载 OneBoardKit
├── App/                    # OneBoardKit 应用层
│   ├── OneBoardApp.swift   # 设置窗口相关类型
│   └── AppDelegate.swift   # 生命周期和 URL Scheme 路由
├── Core/                   # 核心基础设施
│   ├── Database/           # 数据库管理 + 迁移
│   ├── Extensions/         # Swift 扩展
│   ├── Theme/              # 主题色板
│   └── Utilities/          # 工具类
├── Modules/                # 功能模块
│   ├── Clipboard/          # 剪贴板模块
│   ├── Screenshot/         # 截图模块
│   ├── FileStaging/        # 文件暂存模块
│   ├── Gateway/            # 网关切换模块
│   ├── AIModels/           # Codex / Claude Code 模型供应商切换
│   └── CodexAccounts/      # Codex 桌面账号切换模块
├── FinderSync/             # Finder Sync Extension
├── Shared/                 # 共享服务
│   ├── HotkeyManager.swift
│   ├── MenuBarManager.swift
│   ├── FloatingWindowManager.swift
│   ├── FinderFileCreation.swift
│   └── PermissionManager.swift
├── Resources/              # 资源文件
└── Tests/                  # XCTest 回归测试
```

### 可执行模块隔离

`OneBoard` 可执行 target 必须保持极简，业务代码全部位于 `OneBoardKit`。macOS 26 下，不要把业务源码重新并入可执行 target，否则可能干扰 `NSStatusItem` 渲染。

### Finder 新建文件跨进程协议

Finder Sync Extension 运行在 App Sandbox 中，不直接向目标目录写文件：

```text
Finder 右键菜单
  → FinderSyncController 获取 targetedURL/selectedItemURLs
  → oneboard://new-file?directory=...&type=...
  → AppDelegate 接收 URL
  → FinderFileCreator 创建文件
  → Finder 选中新文件
```

- `FinderFileCreationRequest` 只接受绝对目录和 txt/docx/xlsx 白名单类型。
- Finder 监听集合包含 `/`、用户目录、传统 `~/Desktop`、iCloud Desktop 兼容路径和 `FileManager` 解析出的桌面目录；候选路径只用于 Finder Sync 支持的本地目录。
- 每个候选目录同时加入标准化路径与符号链接解析后的路径，兼容桌面迁移到 iCloud 或由符号链接重定向的环境。
- iCloud Drive 及启用 iCloud 同步的桌面由 File Provider 管理，第三方 Finder Sync 无法在其空白处添加菜单；不得通过扩大沙盒权限宣称兼容。
- Finder 扩展 entitlement 仅保留 Desktop 与 iCloud Desktop 兼容路径的读写例外；扩展仍不得绕过主应用直接写文件。
- 文件名从 `未命名.ext` 开始，冲突时依次使用 `未命名 1.ext`、`未命名 2.ext`。

### Codex 账号状态与凭据续期

```text
SQLite 账号凭据
  → 检查 access token exp（提前 5 分钟）
  → 必要时 POST auth.openai.com/oauth/token 刷新并原子保存轮换结果
  → GET chatgpt.com/backend-api/wham/usage
  → 将 used_percent 换算为 remainingPercent
  → 补充账号订阅到期信息
  → 把轮换后的凭据、额度、订阅、重置次数和更新时间写回 SQLite
```

- 后台每 15 分钟顺序刷新账号，避免同一账号并发请求；单账号失败不影响其余账号，并保留上次成功快照。
- `refresh_token` 响应字段可选：服务端未返回新值时必须保留旧值，返回新值时保存轮换后的完整认证缓存。
- 当前账号且 Codex 正在运行时禁止 OneBoard 旋转凭据，避免官方客户端与 OneBoard 重复使用同一 refresh token；切号前只续期尚未运行的目标账号。
- 刷新当前账号状态前先从 Codex 官方 `file` / `keyring` 存储读取最新凭据并同步回 OneBoard vault，避免继续使用已被官方客户端轮换掉的旧 refresh token。
- `wham/usage` 和订阅查询属于 Codex 当前认证服务接口，不视为公开稳定 SDK；字段缺失时显示未知，HTTP/解析失败时显示可恢复错误。

### 截图坐标与 Retina 规则

- 截图像素数据可使用 Retina 像素尺寸，但 AppKit 窗口布局必须使用框选区域的逻辑点尺寸。
- `ScreenshotCropMapper.cropRect` 从 AppKit 左下原点转换到 CGImage 左上原点，裁剪时必须翻转 Y。
- `ScreenshotCropMapper.screenRect` 只叠加屏幕原点，AppKit 窗口定位不得再次翻转 Y。
- 未缩放截图必须严格复用框选区域原点，不能按图片像素尺寸重新居中或上下镜像。
- 只有框选区域超过可见屏幕约束时才进行等比缩放。
- 截图选区分为 selecting、adjusting、locked 三个阶段；只有 adjusting 阶段允许移动和八方向缩放。
- 点击标注或输出工具时只允许执行一次锁定；进入 locked 后所有选区几何事件必须失效。

### 多显示器截图与会话规则

- `ScreenshotCaptureService` 必须为 `NSScreen.screens` 中的每块显示器生成独立捕获计划，并使用 `screencapture -D <displayNumber>` 分别取得原图。
- 每块显示器创建一个与其 `screen.frame` 对齐的可成为 key window 的遮罩窗口；启动时优先激活鼠标所在屏幕的遮罩。
- 每个遮罩只裁剪自己的显示器图像，裁剪映射使用遮罩局部 `bounds`，不得用主屏 frame 或跨屏拼接图推导比例。
- 任意一个遮罩确认或取消后，统一清理所有事件监听和所有遮罩窗口；完成闭包只能恢复 continuation 一次。
- adjusting 和 locked 阶段复用同一个 `AnnotationToolbarView`，不得恢复第二套精简 `ScreenshotSelectionToolbarView`。
- 点击标注工具必须在同一事件链中锁定选区并安装 `AnnotationCanvasView`；第一次落笔发生在画布切换边界时，要把鼠标按下事件转交给 `AnnotationViewModel`，不能吞掉首笔。
- OCR、翻译、复制、保存和贴图是截图会话输出动作，必须先走完成路径关闭所有遮罩，再打开后续窗口或执行输出。
- Google 免费 Web 翻译端点返回 `429` 时提示当前网络被临时限流并建议稍后重试或切换 Apple/已配置 API；非成功 HTML 响应不得把拦截页或 `DOCTYPE` 原文展示在翻译面板。
- `GoogleTranslationService` 的网络会话必须可注入，以便用确定性的 HTTP 响应覆盖限流回归测试。

### 网关 Helper 安全边界

- Helper 当前协议版本为 `ONEBOARD_GATEWAY_HELPER_VERSION=4`；旧版本必须被识别为需要重新安装。
- 安装脚本在一次管理员授权内写入 Helper、sudoers 和初始 IPv4 白名单，白名单去重、排序并过滤非法地址，禁止先创建空白名单再二次提权同步。
- Profile 变化后的白名单同步使用受限 Helper 路径；sudoers 只允许执行 `/usr/local/bin/oneboard-gateway-helper`。
- 网关切换先通过 `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` 确认设备所有者，系统优先使用 Touch ID，并在不可用时回退到 Mac 登录密码。
- `GatewaySwitcher` 在 Helper 缺失、需要密码、无 TTY 或命令不存在时直接要求安装/升级 Helper，不得进入 AppleScript 管理员授权回退。
- `Router/DNS is not allowed` 属于 Helper 的最终业务拒绝，必须直接向上抛错，禁止通过 AppleScript 管理员命令绕过白名单。
- Helper v4 仅增加 `--uninstall` 自卸载命令；卸载通过既有 sudoers 精确路径执行，并在删除 sudoers、白名单和自身前经过 Touch ID/登录密码确认。
- Touch ID 只确认当前设备所有者，不能授予 root；首次安装或升级 Helper 写入系统目录时仍必须由 macOS 完成一次管理员授权。

### Codex 桌面认证缓存切换

- 仅支持 bundle ID 为 `com.openai.codex` 的 Codex/ChatGPT macOS 桌面 App，不处理 Codex CLI。
- 新增账号通过 Codex CLI 标准形态直接请求 `https://auth.openai.com/oauth/authorize`，发起 authorization-code + PKCE 流程，并使用随机 `state` 校验 `localhost` 回调；授权会话 10 分钟超时。
- OAuth 请求使用 `originator=codex_cli_rs`，禁止套用 `https://chatgpt.com/codex/desktop-auth`，也不携带 `codex_app_version`、`source_surface_stable_id`、`codex_origin_stable_id` 等 Codex Desktop 私有参数。
- OAuth 本机回调必须使用授权服务登记的 `http://localhost:1455/auth/callback`；随机端口会在进入登录前被拒绝。
- 密码和验证码由 OpenAI 官方浏览器登录流程处理，OneBoard 不收集也不持久化这些字段；填写的邮箱必须与 `id_token` 中已授权账号一致。
- `CodexAccountProfile`、活动状态和认证缓存统一写入 `~/Library/Application Support/OneBoard/oneboard.sqlite`；认证缓存位于 `private_records/codex_account_auth_cache`。
- OneBoard 将 `~/.codex/config.toml` 顶层 `cli_auth_credentials_store` 强制为 `file`，不读写官方 `Codex Auth` 钥匙串；当前活动凭据只在切换时物化到 `~/.codex/auth.json`。
- 文件读取和恢复前验证非空 JSON 对象并拒绝符号链接，原子替换后权限固定为 `0600`，目录首次创建时权限为 `0700`。
- Codex 运行中禁止替换认证存储。切换请求先校验目标 SQLite 凭据，再请求主应用正常退出；2 秒后仍残留时发送 SIGTERM，之后最长等待 20 秒。
- 退出前通过父子 PID 捕获直属 Codex `app-server`，主进程退出后仍要确认这些旧进程结束，避免旧 token 刷新回写覆盖新账号。
- 切换前先把当前文件写回已知活动账号的 SQLite 记录，使 OpenAI 自动刷新后的 token 不丢失；第一次切换到 OAuth 管理账号时，在 Codex 完全退出后直接接管 `auth.json`。
- 凭据提交后通过 LaunchServices 以新实例重新打开 Codex。关闭失败时必须在提交前停止；启动失败时保留已切换的目标凭据并提示手动打开。

### AI 模型供应商切换

- `AIProviderProfile`（含备注与官网）、当前标记与 API Key 统一存入 OneBoard SQLite；API Key 位于 `private_records/ai_provider_api_key`，普通配置状态位于 `application_state`，不得接入 macOS Keychain。
- Codex 写入器仅合并 `~/.codex/config.toml`：更新顶层 `model_provider` / `model` / `model_catalog_json`，并管理唯一 `[model_providers.oneboard]` 表；自定义供应商原子生成权限为 `0600` 的 `~/.codex/oneboard-model-catalog.json`，目录只包含当前模型并使用供应商名称作为显示名；切回官方时移除目录覆盖，其他顶层字段和 TOML 表原样保留。
- 自定义 Codex 表使用 `wire_api = "responses"`、`requires_openai_auth = false` 和 provider-scoped `experimental_bearer_token`；官方配置移除 OneBoard 表和 `model_provider`，但不修改账号认证缓存。
- Claude Code 写入器解析 `~/.claude/settings.json`（兼容已存在的 `claude.json`），仅替换 `env` 中 OneBoard 管理的 `ANTHROPIC_*` API/模型键，其他 JSON 字段和环境变量保留。
- Claude 受管模型键覆盖 `ANTHROPIC_MODEL`、Haiku/Sonnet/Opus/Fable 的模型 ID 与可选 `*_MODEL_NAME`，以及 `CLAUDE_CODE_SUBAGENT_MODEL`；Haiku/Sonnet/Opus 空值回退默认模型，Fable 空值先回退 Opus 再回退默认模型。
- `ANTHROPIC_AUTH_TOKEN` 与 `ANTHROPIC_API_KEY` 只是同一 SQLite 密钥切换时的目标环境变量；编辑页默认前者并将选择收纳在高级选项，保存位置不随字段选择改变。
- `ProxySidecar/` 固定依赖 CC Switch MIT 源码提交并产出 `Contents/Helpers/oneboard-ai-proxy`。sidecar 只使用 `Database::memory()`，通过 stdin 接收 OneBoard SQLite 快照，通过 stdout 返回动态监听端口，不读写 `~/.cc-switch`。
- 自定义供应商切换先启动/替换 sidecar，再把 Claude 指向本地根地址、Codex 指向本地 `/v1`；两者只写 `PROXY_MANAGED` 占位认证。真实 Key 仅存在于 OneBoard SQLite 与代理进程内存。
- Codex Desktop 运行中切换供应商时复用 `CodexApplicationLifecycleControlling`：代理预检成功后关闭主进程并等待直属 app-server 退出，再原子写入配置、提交活动 ID 并重新打开；关闭失败恢复旧代理且不提交活动 ID，重开失败保留已提交的新配置并提示手动打开。
- 保存当前活动供应商时必须重新执行同一切换链路，使 SQLite 中更新后的 Key/模型同步进入代理内存；非活动配置仍只保存。编辑页另提供“保存并切换”消除保存与启用的歧义。
- 代理运行时复用 CC Switch 的 Claude/Codex 协议转换、SSE、请求头/请求体覆盖、完整 URL及端点策略；客户端配置备份、原子写入和恢复仍由 OneBoard 管理。
- 编辑器根据主机名识别 `api.deepseek.com` 及其子域并默认选择 OpenAI Chat Completions；协议、User-Agent、备用端点、请求覆盖和缓存路由属于高级兼容项，默认折叠，已保存和导入值不得丢失。
- 模型页官方额度复用 `CodexAccountProfile.status`；第三方通过内置接口读取，失败保留带时间的旧快照并显示错误，不得执行从 CC Switch 静默导入的 JavaScript 用量脚本。
- 两种写入都拒绝符号链接，使用 Foundation atomic replace，将目标文件设为 `0600`；首次写入创建 `<filename>.oneboard-backup` 且后续不覆盖。
- Claude Code 切换仅影响新启动的 CLI 会话；Codex Desktop 切换会安全退出并重新打开应用，确保长期驻留的 app-server 重读 provider 配置。
- CC Switch 导入器以只读方式打开 `~/.cc-switch/cc-switch.db`，只接收 Codex / Claude；API Key 直接写入 `private_records`，导入 Claude 角色模型、显示名、代理元数据和备用端点，保存运行快照前剥离其中的明文 Key；空白或缺少必要字段的配置显式跳过。
- 数据库目录固定为 `0700`，主库及已存在的 WAL/SHM 固定为 `0600`；测试必须注入临时数据库、认证文件和可控进程生命周期，禁止读取或修改用户真实认证缓存。

### 文件摇晃检测降级

- 有输入监听授权时启用 `CGEventTap`，并持续使用轮询作为补充。
- 没有输入监听授权时不能终止整个检测器；必须保留鼠标状态和 drag pasteboard 轮询通道。
- 文件拖拽不能只凭 pasteboard 类型确认，必须读取真实 file URL 并验证目标是普通文件。
- 常规扩展名不设白名单；以文件系统 `isRegularFile` 为准，同时显式拒绝 `.app`、目录和不可读取 URL。
- 已确认的文件拖拽在同一轮手势中保持确认状态，不能只依赖 pasteboard `changeCount` 变化。

## 数据模型

### clipboard_history

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK AUTOINCREMENT | |
| contentType | TEXT NOT NULL | text/rtf/html/image/fileURL |
| plainText | TEXT | 纯文本缓存 |
| data | BLOB NOT NULL | 原始数据 |
| sourceAppBundleId | TEXT | 来源应用 |
| isPinned | BOOLEAN DEFAULT false | 置顶 |
| createdAt | DATETIME NOT NULL | 创建时间 |

### staged_files

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK AUTOINCREMENT | |
| fileName | TEXT NOT NULL | |
| fileURL | TEXT NOT NULL | |
| fileSize | INTEGER NOT NULL | |
| bookmarkData | BLOB | 安全域书签 |
| thumbnailData | BLOB | 缩略图 PNG |
| stagedAt | DATETIME NOT NULL | |

## 权限要求

| 权限 | 用途 | 请求方式 |
|------|------|---------|
| 辅助功能 | 全局快捷键、模拟粘贴 | AXIsProcessTrusted() |
| 输入监听 | 全局拖拽事件监听 | CGPreflightListenEventAccess() |
| 屏幕录制 | 截图功能 | 系统自动弹窗 |
| Finder 扩展 | Finder 右键快速新建 | 系统扩展管理页启用 |
| 开机自启 | SMAppService | 代码注册 |

## 编码规范

1. 使用 Swift 命名惯例（UpperCamelCase 类型、lowerCamelCase 方法/属性）
2. 所有 UI 相关代码使用 `@MainActor`
3. 数据库操作使用 `async throws`
4. 避免强制解包，使用 `guard let` / `if let`
5. 使用 `print` 进行日志输出（后续可替换为 os.Logger）
6. 中文注释和文档

## 2026-09-05 模型目录选择与额度说明

模型槽位使用 NSComboBox 接入 discoveredModels，通过现有模型基础 ID Binding 保留 1M 标记。API Key、请求地址或完整 URL 设置变更立即失效目录；请求标识阻止旧异步响应回填。

## 2026-09-05 第三方额度、Token 统计与翻译 Key 选择

- 额度：内置 DeepSeek、Sub2API、SiliconFlow、OpenRouter 查询。自动识别官方域名，其他同源地址尝试 Sub2API `/v1/usage`；可在编辑页选择额度接口类型。失败显示 HTTP 状态及服务端原因，旧快照标明时间；不执行导入脚本。
- 统计：按 API Key 和供应商源分组，展示当日、累计、缓存命中 Token，展开查看输入、输出和缓存写入。相同 Key 的 Codex/Claude 配置共享本地统计，换 Key 后分开计算。
- 数据源：Sub2API 有历史用量时展示供应商当日/累计快照；OneBoard 本地统计仅覆盖启用后通过内置代理或翻译的请求，按本机时区计算自然日，包含缓存 Token 且不重复相加，不与供应商统计合计。余额接口未返回 Token 时不推算历史 Token。
- 存储：代理复用 CC Switch 的响应解析，向 stdout 输出无正文、无 Key 的计数事件；主应用写入 oneboard.sqlite 的 ai_usage_events，按请求 ID 去重。Key 仍仅在 SQLite 和代理内存中；正常退出刷新尾部计数，异常强杀可能丢失尚未输出的短暂内存事件。
- 翻译：设置页选择默认 API Key；翻译窗口可临时切换具体供应商配置，复用其默认模型、连接及协议，支持 Chat Completions、Responses、Anthropic Messages 和 Gemini；不改变 Codex/Claude 活动配置，也不再单独填写 DeepSeek Key。

## 2026-09-05 设置页整体视觉升级

设置专属 SettingsPalette / SettingsBackdrop / SettingsCard / SettingsForm 集中管理视觉。SettingsForm 使用 macOS 15 的 ForEach(sections:) 读取既有 Section，统一卡片、行间距、LabeledContent 和 Toggle 布局；不修改全局 OneBoardColors，避免影响截图与浮动工具。AIProviderSettingsCard 分离展示，保留供应商/本地统计来源及完整折叠明细。

## 2026-09-05 功能导航与独立面板

SettingsTab 新增 translation 和 files，保留 general / recognition / todo 的持久化标识。FileSettingsView 接管 Finder 文件类型绑定及共享 UserDefaults 持久化，TodoSettingsView 只管理待办行为。MenuBarManager.makeMainMenu 负责原生菜单分组，快捷动作调用现有窗口管理器，菜单跟随系统外观。

FeaturePanelDesign 复用 SettingsPalette 和 SettingsBackdrop，提供独立面板的语义色、标题和带辅助功能标签的图标按钮。仅操作面板及其行视图使用这些令牌；不变更截图画布、标注工具栏的视觉与会话流程。网关面板展示已有 statusMessage，剪贴板页脚读取真实保留天数。

移除无调用的 StagedFileRowView、View+Extensions.swift 旧按钮/悬停/卡片/面板封装、旧颜色别名，以及文件窗口创建的多余转发。保留数据迁移和仍使用的系统版本、格式及协议兼容分支。

## 2026-09-05 截图与文件拖拽

`ScreenshotWindowCandidate` 在创建遮罩前按 WindowServer 层级顺序获取普通窗口，过滤透明与过小窗口，用主屏高度将 Quartz 坐标转换为 AppKit 坐标，再裁到每屏本地坐标。Overlay 的预选独立于已提交选区：4pt 内点击采用候选，拖动改为自定义；键盘仅由所属遮罩处理。

贴图显式读取最高像素的 bitmap CGImage，禁用 SwiftUI 插值，hosting view 初始 frame 使用选区逻辑尺寸。标注导出保留原像素；截图完成 continuation 在遮罩清理后恢复。DragDetector 在空闲、按下和松手时记录 .drag changeCount，只接受本轮新写入且可读的普通文件；所有鼠标源统一 AppKit 坐标。

### 窗口预选稳定性修正（2026-09-05）

修正透明预选区的输入穿透风险：Overlay 先绘制不透明底色与 cachedCGImage，再以 even-odd 填充选区外暗色；不再清空选区 alpha。窗口设置 isOpaque=true。窗口点击暂存 anchor/candidate，不提前修改 selectionModel；超过 4pt 时用原 anchor 开始框选，mouseUp 解析点击或无中间事件的拖动。mouseEntered 同步悬停候选。

### 2026-09-05 翻译、授权与列表性能

截图工具栏 HostingView 接受首次鼠标点击；向上传递的工具栏鼠标序列不得进入选区状态机。输出仍经 `finishToolbarOutput` / 截图会话关闭全部遮罩后进入 OCR 与翻译。选中文字先检查辅助功能权限，再优先读取 AX，必要时模拟复制；空白结果静默返回。

网关以 Helper 版本、sudoers/白名单文件及 `sudo -n -l` 的只读授权检查判断准备状态。缺失时执行既有安装流程，安装成功才执行设备身份验证；业务白名单拒绝不触发管理员 shell 回退。授权后重新读取网络快照。面板失焦/外部点击处理在切换期间暂停自动关闭。

DeepSeek 官方源不继承 Anthropic 兼容路径的额度前缀。额度使用独立错误类型，Token 持久化继续按源与 Key 分组。后台 ImageIO 生成最大 56px 的列表缩略图，NSCache 上限 256 张 / 8MB，原图仍用于复制粘贴。预览只读取前 100 字。

iCloud 根容器、桌面目录、系统解析目录与符号链接目标同步纳入扩展监听及权限。主应用的桌面新建入口使用 FileManager 的 desktopDirectory，并解析符号链接后调用既有文件创建器；不改变 iCloud 设置，不承诺解除 File Provider 的菜单限制。

### 2026-09-05 设置首次打开崩溃修复

SystemCapabilityViewModel 的 refresh 及 Helper 安装/卸载后状态检查通过 Task.detached 执行，再回到 MainActor 更新状态。禁止 Process.waitUntilExit 在单例初始化期间运行主线程嵌套 RunLoop。

## 2026-09-06 同步与新增工具技术边界

- `CloudKitConfigurationStore` 只访问 `iCloud.com.oneboard.mac` 的 private database；单一版本化 JSON 快照承载白名单 UserDefaults、App Group 文件类型、`application_state` 与除 `ai_quota` 外的 `private_records`。
- `CloudSyncViewModel` 延迟创建 `CKContainer`。本地包使用不含 CloudKit 键的 `OneBoard.local.entitlements` 并写入能力标记；仅持有有效 iCloud provisioning profile 的发布构建可设置 `ONEBOARD_ENABLE_ICLOUD_SYNC=1` 使用完整 entitlement。
- 云端快照覆盖配置表以传播删除；`ai_quota` 与 `ai_usage_events` 保留本机。偏好与 SQLite 配置变化防抖 2 秒上传，远端应用后通知供应商、账号与菜单栏刷新。
- Finder Sync 复用目标目录解析，只发送 `oneboard://open-terminal?directory=...`；主应用通过 `NSWorkspace` 打开系统 Terminal，不由扩展执行 shell。
- 长截图按原选区定位显示器，使用独立 `screencapture -D` 重抓、CGEvent 像素滚动、相邻帧静止检测和固定重叠裁剪；不得改变多显示器独立捕获约束。
- 自定义翻译继续复用 `AIProviderProfile`、`SQLiteAIProviderSecretVault` 与 `ConfiguredAITranslationService`，默认使用 OpenAI Chat Completions，不复制新的明文 Key 存储。
# 2026-09-06 实现约束

- 拖拽显示由本次 `.drag` changeCount 与可读普通文件 URL 共同确认，同一次拖拽只通知一次。
- AI OCR 复用 `AIProviderProfile` 和 SQLite 密钥，按 OpenAI Chat/Responses、Anthropic、Gemini 图片输入格式构造请求。
- 菜单栏状态项的创建和移除由 `MenuBarManager` 统一管理；网速标题按上传、下载两行渲染。


## 2026-09-07 iCloud 授权与 Claude Code 账号

- 文件夹授权按规范化文件系统路径校验，忽略目录 URL 末尾斜杠；授权错误显示在对应行。选择后立即重试已开启的备份，异步读写期间保持安全作用域访问。
- 授权状态与操作统一样式，文件夹使用已连接状态、更改和断开操作。
- 新增独立 Claude Code 账号页，复用 AI 模型配置与 SQLite 授权，支持添加、切换、编辑、重新授权和删除；切换后新会话生效。
- 内置代理检测父进程存活；OneBoard 强退或崩溃后代理自行停止并释放端口，正常退出继续使用既有清理路径。

Claude Code 账号页不展示共享的供应商切换状态，避免串入 Codex 提示；仅显示本页操作错误。

Claude Code 授权页与 Codex 统一标题、待授权账号、OAuth 卡片、浏览器等待状态、链接复制及取消操作；按 Claude 授权流程保留授权码回填，账号输入位于弹窗内。
