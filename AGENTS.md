# AGENTS.md

OneBoard 是一个 macOS 原生应用，整合截图、历史剪贴板和文件暂存三大功能。

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

## 构建与打包

```bash
# 开发测试（不污染正式 Bundle ID）
ONEBOARD_BUNDLE_ID_SUFFIX=.dev bash script/build_app_bundle.sh

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
2. 修改后 `swift build` 验证
3. 修 bug 前查根因，修后验证，修复后重新打包校验 DMG
