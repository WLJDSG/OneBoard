# OneBoard

macOS 原生截图、历史剪贴板、文件暂存、Finder 快速新建、网关切换和 Codex 桌面账号切换一体化工具。

当前版本已针对 Apple Silicon（包括 MacBook Air M3）和 macOS 26 的混合 Retina 多显示器、Finder 扩展及菜单栏交互进行适配。

## 功能

### 截图模块

- **自定义遮罩截图**：半透明暗色遮罩，松开鼠标后保留选区，可移动并通过四边、四角调整大小
- **多显示器独立捕获**：每块显示器单独截图并创建对应遮罩，在外接屏框选时只裁剪该屏幕图像，避免混合缩放比例导致错位
- **原位标注锁定**：工具栏跟随选区；点击任意标注工具后锁定当前区域并原位进入标注，锁定后不再改变截图范围
- **统一完整工具栏**：调整和标注阶段复用同一套完整工具栏，不再维护容易行为漂移的精简工具栏
- **坐标稳定**：裁剪像素与 AppKit 屏幕坐标分开换算，顶部选区不会上下镜像到屏幕底部
- **像素尺寸预览**：选区右上角实时 W×H
- **方向键微调**：方向键 1px，Shift+10px 调整选区
- **智能窗口截图**：鼠标悬浮自动高亮窗口轮廓，单击截取
- **标注工具**：矩形、椭圆、箭头、直线、文字（微信风格）、编号圆圈、马赛克
- **粗细循环**：± 按钮到达边界自动循环
- **OCR 文字识别**：先结束截图遮罩会话，再显示弹性结果气泡，避免结果被遮罩覆盖
- **翻译**：Apple Translation / Google / DeepSeek AI；Google 免费端点被限流时显示可操作提示，不展示服务端 HTML
- **贴图置顶**：截图悬浮在所有窗口之上
- **撤销/重做**：无限步操作历史

### 剪贴板模块

- 全类型记录（文字/图片/文件）
- 搜索、置顶、删除
- 时间倒序 + 保留策略（按天数/条数）

### 文件暂存模块

- 拖拽普通文件晃动触发暂存区；txt、表格、图片、压缩包等常规文件均可使用
- 应用窗口、目录和 `.app` 应用包不会触发或进入暂存区；输入监听未授权时保留轮询降级通道
- 文件暂存 + 全局置顶 + 拖出发送

### Finder 快速新建

- 在 Finder 文件夹、桌面和其他目录的右键菜单中快速创建 txt/docx/xlsx
- Finder 扩展只负责获取目标目录，实际写入交由 OneBoard 主应用，避免扩展沙盒导致“没有权限”
- 同时识别本地 Desktop、iCloud Drive 桌面容器根目录、iCloud Desktop、系统解析出的桌面目录及其符号链接目标
- 自动处理重名文件，并在创建后通过 Finder 选中新文件

### 网关切换

- 网关与 DNS 配置快速切换
- OneBoard 专属 Helper 只允许配置档中的合法 IPv4；安装 Helper 与写入初始白名单共用一次管理员授权
- Helper 返回“地址不在白名单”时直接报错，不回退到管理员密码命令，避免绕过白名单边界
- 紧凑型菜单栏弹窗和独立配置页

### Codex 桌面账号切换

- 填写 OpenAI 账号邮箱后直接打开 Codex 标准 OAuth 授权页，浏览器授权成功后自动新增或更新账号；不经过 Codex Desktop 私有中转页
- 管理多个 Codex/ChatGPT 桌面 App 登录缓存，支持重命名、删除和快速切换
- 每个账号展示 5 小时与每周剩余额度、重置时间、订阅到期时间和剩余主动重置次数，并在后台每 15 分钟自动更新
- access token 临近到期、额度请求返回未授权或切号前会自动使用 refresh token 续期；服务端轮换后的凭据继续只保存在钥匙串
- 密码与验证码始终只在 OpenAI 官方网页输入；OneBoard 不保存密码或验证码，认证缓存保存在 macOS 钥匙串
- 菜单栏可快速选择账号；OneBoard 会先正常退出 Codex，超时时对已捕获的残留进程发送终止信号
- 确认 Codex 主进程和旧 `app-server` 完全退出后才切换凭据，完成后自动重新打开 Codex
- 兼容 Codex 官方 `file` / `keyring` / `auto` 凭据存储模式
- 为避免 refresh token 被两个客户端同时使用，当前账号正在 Codex 中运行时 OneBoard 会暂缓凭据轮换，退出 Codex 后自动重试

### 其他

- 全局快捷键自定义
- 菜单栏常驻图标
- 开机自启

## 技术栈

- Swift 5.9+ / SwiftUI + AppKit
- macOS 14.0+
- SQLite (GRDB.swift)
- SPM 依赖管理

## 构建

```bash
cd OneBoard
swift test --disable-sandbox
swift build -c release --disable-sandbox
cd ..
ONEBOARD_CODESIGN_IDENTITY=- script/package_app.sh
hdiutil verify build/OneBoard.dmg
```

最终交付产物为 `build/OneBoard.dmg`。完整验收流程见 [打包与修复流程](docs/打包与修复流程/README.md)。

## 项目结构

```
OneBoard/
├── App_minimal/      # 极简可执行入口，只创建 NSStatusItem 并启动应用
├── App/              # OneBoardKit 生命周期与设置窗口
├── Core/             # 基础设施
├── Modules/
│   ├── Clipboard/    # 剪贴板模块
│   ├── Screenshot/   # 截图模块
│   ├── FileStaging/  # 文件暂存模块
│   ├── Gateway/      # 网关切换模块
│   └── CodexAccounts/# Codex 桌面账号切换模块
├── FinderSync/       # Finder Sync Extension
├── Shared/           # 共享服务与 Finder 新建文件协议
├── Resources/        # 资源文件
└── Tests/            # XCTest 回归测试
```

## 文档

- [需求文档](docs/需求文档/README.md)
- [技术规范](docs/技术规范/README.md)
- [设计规范](docs/设计规范/README.md)
- [开发步骤](docs/开发步骤/README.md)
- [打包与修复流程](docs/打包与修复流程/README.md)
- [开发日志](开发日志/)
