# CLAUDE.md

OneBoard 是一个 macOS 原生应用，整合截图、历史剪贴板和文件暂存三大功能。

## 项目信息

- **语言**：Swift 5.9+
- **UI 框架**：SwiftUI + AppKit
- **目标平台**：macOS 14.0+
- **数据库**：SQLite（GRDB.swift）
- **依赖管理**：Swift Package Manager

## 标准文件路径指引

| 文件 | 路径 | 说明 |
|------|------|------|
| 需求文档 | [docs/需求文档/README.md](docs/需求文档/README.md) | 功能需求详情 |
| 技术规范 | [docs/技术规范/README.md](docs/技术规范/README.md) | 技术栈、架构、编码规范 |
| 设计规范 | [docs/设计规范/README.md](docs/设计规范/README.md) | UI 色彩、布局、交互规范 |
| 开发步骤 | [docs/开发步骤/README.md](docs/开发步骤/README.md) | 各阶段开发任务列表 |
| 开发日志 | [开发日志/](开发日志/) | 按月份组织，每天一个文件 |

## 开发日志规范

开发日志位于 `开发日志/YYYY-MM/YYYY-MM-DD.md`，每天一个文件，记录：
- 当日完成的开发事项
- 待办事项
- 遇到的已知问题
- 备注

## 项目结构

```
OneBoard/          # 源代码（SPM 项目）
├── App/           # 应用入口
├── Core/          # 核心基础设施
├── Modules/       # 功能模块
│   ├── Clipboard/ # 剪贴板模块
│   ├── Screenshot/ # 截图模块
│   └── FileStaging/ # 文件暂存模块
├── Shared/        # 共享服务
└── Resources/     # 资源文件
```

## 构建命令

```bash
# 构建项目
cd OneBoard && swift build

# 清理构建
cd OneBoard && rm -rf .build && swift build

# 运行（当前为命令行模式，后续需要创建 .app bundle）
cd OneBoard && swift run
```

## 编码规范

1. 遵循 Swift 命名惯例
2. UI 代码使用 `@MainActor`
3. 数据库操作使用 `async throws`
4. 避免强制解包
5. 中文注释
6. 修改代码后必须先 `swift build` 验证编译通过

## 当前开发状态

- **第一阶段**（剪贴板模块）：✅ 已完成
- **第二阶段**（截图模块）：待开始
- **第三阶段**（文件暂存模块）：待开始
- **第四阶段**（收尾打磨）：待开始

## 工作说明

1. 每次修改代码前，先阅读相关文档了解需求和设计规范
2. 修改代码后，运行 `swift build` 确保编译通过
3. 每天结束时，更新开发日志
4. 新功能完成后，更新 `docs/开发步骤/README.md` 中的状态
5. 遇到技术问题，先查阅 `docs/技术规范/README.md`
6. UI 相关修改，参考 `docs/设计规范/README.md`