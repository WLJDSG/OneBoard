# CLAUDE.md

OneBoard 是一个 macOS 原生应用，整合截图、历史剪贴板、文件暂存、Finder 快速新建和网关切换。

## 项目信息

- **语言**：Swift 5.9+
- **UI 框架**：SwiftUI + AppKit
- **目标平台**：macOS 14.0+
- **数据库**：SQLite（GRDB.swift）
- **依赖管理**：Swift Package Manager
- **Bundle ID**：`com.oneboard.mac`

## 标准文件路径指引

| 文件 | 路径 | 说明 |
|------|------|------|
| 需求文档 | [docs/需求文档/README.md](docs/需求文档/README.md) | 功能需求详情 |
| 技术规范 | [docs/技术规范/README.md](docs/技术规范/README.md) | 技术栈、架构、编码规范 |
| 设计规范 | [docs/设计规范/README.md](docs/设计规范/README.md) | UI 色彩、布局、交互规范 |
| 开发步骤 | [docs/开发步骤/README.md](docs/开发步骤/README.md) | 各阶段开发任务列表 |
| 打包与修复流程 | [docs/打包与修复流程/README.md](docs/打包与修复流程/README.md) | DMG 打包方法与修 bug 闭环 |
| 开发日志 | [开发日志/](开发日志/) | 按月份组织，每天一个文件 |

## 开发日志规范

开发日志位于 `开发日志/YYYY-MM/YYYY-MM-DD.md`，每天一个文件，记录：
- 当日完成的开发事项
- 待办事项
- 遇到的已知问题
- 备注

## 项目结构（模块隔离架构）

```
OneBoard/                        # SPM 项目根目录
├── App_minimal/                 # 可执行入口模块（极简，仅 main.swift）
│   └── main.swift               # 创建 NSStatusItem + 启动应用
├── App/                         # 应用核心（OneBoardKit 模块）
│   ├── AppDelegate.swift        # 生命周期管理
│   └── OneBoardApp.swift        # SettingsWindowManager + SettingsView
├── Core/                        # 核心基础设施
├── Modules/                     # 功能模块
│   ├── Clipboard/               # 剪贴板模块
│   ├── Screenshot/              # 截图模块
│   ├── FileStaging/             # 文件暂存模块
│   └── Gateway/                 # 网关切换模块
├── FinderSync/                  # Finder Sync Extension
├── Shared/                      # 共享服务
│   └── MenuBarManager.swift     # 菜单栏配置 + 浮动窗口管理
├── Resources/                   # 资源文件
└── Tests/                       # XCTest 回归测试
```

**架构说明**：可执行模块 `OneBoard` 必须保持极简（只含 `main.swift`），所有业务代码在 `OneBoardKit` 库模块中。这是为了兼容 macOS 26——同模块编译时会干扰 NSStatusItem 渲染。

## 构建命令

```bash
# 清理构建
cd OneBoard && rm -rf .build && swift build

# 开发模式构建（自动加 .dev 后缀，不污染正式 Bundle ID）
ONEBOARD_BUNDLE_ID_SUFFIX=.dev bash script/build_app_bundle.sh

# 正式构建 app bundle
ONEBOARD_CODESIGN_IDENTITY=- bash script/build_app_bundle.sh

# 打包 DMG（开发测试，跳过签名）
ONEBOARD_CODESIGN_IDENTITY=- bash script/package_app.sh
```

## 打包规范

- 用户要求打包时，只需要生成 DMG 安装包：`build/OneBoard.dmg`
- DMG 内包含：`OneBoard.app`、`Applications` 软链接、`卸载残留.command`
- 标准命令：`script/package_app.sh`
- 本地测试或证书不可用时：`ONEBOARD_CODESIGN_IDENTITY=- script/package_app.sh`
- 打包后必须执行：`hdiutil verify build/OneBoard.dmg`
- 详细流程见 `docs/打包与修复流程/README.md`

## Bundle ID 管理

**正式 ID**：`com.oneboard.mac`（在 `Resources/Info.plist` 中定义）

**防止 Bundle ID 污染**：
- macOS 26 的 Launch Services 数据库无法手动清除旧 Bundle ID 记录
- 重复安装/卸载同一 Bundle ID 会累积状态，最终导致菜单栏图标不可见
- 开发测试时使用 `ONEBOARD_BUNDLE_ID_SUFFIX=.dev` 给正式 ID 加后缀

**卸载**：
- App 菜单 → 「彻底卸载并清理残留...」（清理所有系统残留后提示手动拖垃圾桶）
- 或 DMG 中双击 `卸载残留.command`
- 或命令行执行 `bash script/uninstall.sh`

## 编码规范

1. 遵循 Swift 命名惯例
2. UI 代码使用 `@MainActor`
3. 数据库操作使用 `async throws`
4. 避免强制解包
5. 中文注释
6. 修改代码后必须先 `swift build` 验证编译通过

### 功能实现边界

- 多显示器截图按显示器独立捕获、独立显示遮罩、独立裁剪，不能依赖主屏逻辑尺寸处理外接屏图像。
- 选区调整和标注阶段复用完整 `AnnotationToolbarView`；标注工具点击即锁定并安装画布，OCR 等输出动作先结束截图会话再打开结果窗口。
- Finder Sync 不直接创建文件；本地 Desktop、iCloud Desktop、系统解析桌面目录和符号链接目标必须一并纳入监听与权限配置。
- 网关切换、Helper 卸载和 App 内彻底卸载使用 Touch ID 优先的设备所有者验证；首次安装/升级 Helper 仍保留一次系统管理员授权。Helper 缺失或白名单拒绝是最终错误，不允许回退到管理员密码 shell。

## 当前开发状态

- **剪贴板、截图、文件暂存**：✅ 已完成并持续维护
- **Finder 快速新建、网关切换、待办事项**：✅ 已完成并持续维护
- **当前重点**：macOS 26 兼容、真实交互回归与发布包验证

## 开发工作流（重要）

**每次修完 bug 或写完新特性后，必须执行以下流程让用户看到效果：**

1. 先卸载旧版 App（App 菜单 → 「彻底卸载并清理残留...」或 `bash script/uninstall.sh`）
2. 构建最新版 app bundle：`ONEBOARD_BUNDLE_ID_SUFFIX=.dev bash script/build_app_bundle.sh`
3. 打开最新版 app：`open build/OneBoard.app`
4. 告知用户 app 已启动，请用户验证效果

> **原因**：直接覆盖安装旧版 app 可能导致 Bundle ID 缓存问题，菜单栏图标不可见。

## 工作说明

1. 每次修改代码前，先阅读相关文档了解需求和设计规范
2. 修改代码后，运行 `swift build` 确保编译通过
3. 每天结束时，更新开发日志
4. 新功能完成后，更新 `docs/开发步骤/README.md` 中的状态
5. 遇到技术问题，先查阅 `docs/技术规范/README.md`
6. UI 相关修改，参考 `docs/设计规范/README.md`
7. 修 bug 前必须先确定影响范围和复现条件，查清根因后做最小修复
8. 修 bug 后必须验证；如果未修复，继续分析和修复，直到验证通过
9. bug 修复完成后必须重新执行打包流程，生成并校验 `build/OneBoard.dmg`

## 2026-09-06 供应商、授权与截图补充

供应商模板自动配置端点；完整推理 URL 与模型目录独立解析，手动额度缓存按接口区分。目录书签仅留本机，禁止启动探测未授权 iCloud 目录。后台备份无变化不发布进度、不重写。拖拽只在成功投放持久化，取消还原；设置内容不得拖动窗口。字号 1–20 循环；文字拖动用固定画布坐标；框选标注作为单层撤销。取色实时 sRGB 与 Command+C 复制，使用每屏原始截图。长截图不得用四块全屏遮罩形成大框，只保留角标、完成栏与预览；歧义匹配不追加。
