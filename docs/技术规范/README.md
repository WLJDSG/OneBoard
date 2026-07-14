# OneBoard 技术规范

## 技术栈

| 层级 | 技术 | 版本要求 |
|------|------|---------|
| 语言 | Swift | 5.9+ |
| UI 框架 | SwiftUI + AppKit | macOS 15.0+ |
| 数据库 | GRDB.swift | 6.x |
| 全局快捷键 | KeyboardShortcuts | 2.x |
| 开机自启 | LaunchAtLogin | 4.x |
| OCR | Apple Vision | macOS 内置 |
| 翻译 | Apple Translation / Google Web / DeepSeek | macOS 15.0+ |
| 截图 | CoreGraphics / ScreenCaptureKit | macOS 内置 |
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
│   └── Gateway/            # 网关切换模块
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
- Finder 监听集合包含 `/`、用户目录和 Desktop；Desktop 空白处没有目标 URL 时回退到真实桌面目录。
- 文件名从 `未命名.ext` 开始，冲突时依次使用 `未命名 1.ext`、`未命名 2.ext`。

### 截图坐标与 Retina 规则

- 截图像素数据可使用 Retina 像素尺寸，但 AppKit 窗口布局必须使用框选区域的逻辑点尺寸。
- `ScreenshotCropMapper.cropRect` 从 AppKit 左下原点转换到 CGImage 左上原点，裁剪时必须翻转 Y。
- `ScreenshotCropMapper.screenRect` 只叠加屏幕原点，AppKit 窗口定位不得再次翻转 Y。
- 未缩放截图必须严格复用框选区域原点，不能按图片像素尺寸重新居中或上下镜像。
- 只有框选区域超过可见屏幕约束时才进行等比缩放。
- 截图选区分为 selecting、adjusting、locked 三个阶段；只有 adjusting 阶段允许移动和八方向缩放。
- 点击标注或输出工具时只允许执行一次锁定；进入 locked 后所有选区几何事件必须失效。

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
