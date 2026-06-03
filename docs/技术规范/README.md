# OneBoard 技术规范

## 技术栈

| 层级 | 技术 | 版本要求 |
|------|------|---------|
| 语言 | Swift | 5.9+ |
| UI 框架 | SwiftUI + AppKit | macOS 14.0+ |
| 数据库 | GRDB.swift | 6.x |
| 全局快捷键 | KeyboardShortcuts | 2.x |
| 开机自启 | LaunchAtLogin | 4.x |
| OCR | Apple Vision | macOS 内置 |
| 翻译 | Apple Translation | macOS 14.4+ |
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
├── App/                    # 应用入口
│   ├── OneBoardApp.swift   # @main
│   ├── AppDelegate.swift   # 生命周期管理
│   └── AppSettings.swift   # UserDefaults 设置
├── Core/                   # 核心基础设施
│   ├── Database/           # 数据库管理 + 迁移
│   ├── Extensions/         # Swift 扩展
│   ├── Theme/              # 主题色板
│   └── Utilities/          # 工具类
├── Modules/                # 功能模块
│   ├── Clipboard/          # 剪贴板模块
│   ├── Screenshot/         # 截图模块
│   └── FileStaging/        # 文件暂存模块
├── Shared/                 # 共享服务
│   ├── HotkeyManager.swift
│   ├── MenuBarManager.swift
│   ├── FloatingWindowManager.swift
│   └── PermissionManager.swift
└── Resources/              # 资源文件
```

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
| 屏幕录制 | 截图功能 | 系统自动弹窗 |
| 开机自启 | SMAppService | 代码注册 |

## 编码规范

1. 使用 Swift 命名惯例（UpperCamelCase 类型、lowerCamelCase 方法/属性）
2. 所有 UI 相关代码使用 `@MainActor`
3. 数据库操作使用 `async throws`
4. 避免强制解包，使用 `guard let` / `if let`
5. 使用 `print` 进行日志输出（后续可替换为 os.Logger）
6. 中文注释和文档