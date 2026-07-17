# AGENTS.md

OneBoard 是一个 macOS 原生应用，整合截图、历史剪贴板、文件暂存、Finder 快速新建和网关切换。

## 项目信息

- **语言**：Swift 5.9+
- **UI 框架**：SwiftUI + AppKit
- **目标平台**：macOS 14.0+
- **数据库**：SQLite（GRDB.swift）
- **依赖管理**：Swift Package Manager
- **Bundle ID**：`com.oneboard.mac`

## 项目结构（模块隔离架构）

```
OneBoard/                        # SPM 项目根目录
├── App_minimal/                 # 可执行入口（极简，仅 main.swift）
│   └── main.swift               # 创建 NSStatusItem + 启动应用
├── App/                         # OneBoardKit 模块
│   ├── AppDelegate.swift        # 生命周期
│   └── OneBoardApp.swift        # 设置窗口
├── Core/                        # 基础设施
├── Modules/                     # 功能模块
├── Shared/                      # 共享服务
│   └── MenuBarManager.swift     # 菜单栏配置 + 浮动窗口
└── Resources/                   # 资源文件
```

> ⚠️ **架构约束**：可执行模块必须极简。所有业务代码放 `OneBoardKit` 库中。
> 同模块编译会干扰 macOS 26 的 NSStatusItem 渲染。详见 `开发日志/2026-06/2026-06-26.md`

## 不可破坏的实现规则

1. 多显示器截图必须按 `NSScreen.screens` 为每块显示器独立执行 `screencapture -D` 并创建对应遮罩；不得把不同缩放比例的屏幕拼成一张图后按主屏尺寸裁剪。
2. 截图阶段必须复用完整 `AnnotationToolbarView`。点击标注工具后立即锁定选区并安装画布；OCR、翻译、复制、保存和贴图必须经过截图会话完成路径，先关闭所有遮罩。
3. Finder Sync 只负责生成 `oneboard://new-file` 请求，文件写入由主应用完成。桌面监听必须覆盖本地/iCloud/系统解析目录及符号链接目标，沙盒权限与目录集合要同步修改。
4. 网关 Helper 安装和初始白名单写入必须在一次管理员授权内完成；Helper 的白名单业务拒绝不得回退到管理员密码执行。

## 构建与打包

```bash
# 全量测试和 Release 构建（SPM 根目录）
cd OneBoard
swift test --disable-sandbox
swift build -c release --disable-sandbox
cd ..

# 开发测试（不污染正式 Bundle ID）
ONEBOARD_BUNDLE_ID_SUFFIX=.dev2 bash script/build_app_bundle.sh

# 正式打包
ONEBOARD_CODESIGN_IDENTITY=- bash script/package_app.sh
hdiutil verify build/OneBoard.dmg

# 卸载
bash script/uninstall.sh
```

## 卸载

- App 菜单 → 「彻底卸载并清理残留...」
- DMG 中双击 `卸载残留.command`
- 命令行：`bash script/uninstall.sh`

## 编码规范

1. Swift 命名惯例 | `@MainActor` UI | `async throws` 数据库 | 中文注释
2. 修改后从 `OneBoard/` 运行全量测试和 Release 构建
3. 修 bug 前查根因并补回归测试，修后重新打包并执行 `hdiutil verify build/OneBoard.dmg`
4. 行为变化必须同步更新 README、需求/技术/设计/开发步骤、规则文件和当天开发日志
