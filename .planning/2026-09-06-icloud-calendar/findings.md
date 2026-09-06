# Findings

## 参考图

- 左侧有独立“iCloud 同步”和“日历”设置入口。
- 日历核心配置包含每周开始于周一/周日/关闭，以及“显示日历图标”总开关。
- 用户明确要求的是日历功能和菜单栏显示可配置；钉到桌面等参考图附加能力不纳入本次范围。
- 第二张参考图确认 Finder 右键需要“进入终端”和“长截图”入口；其他第三方菜单项不在范围内。
- 翻译参考图的稳定信息：顶部引擎卡片、服务商预设、Base URL、API Key、模型名、获取模型、测试连接和翻译行为分区。
- 用户明确要求三类引擎为系统、Google、自定义 API；参考图中只有两类的布局不能覆盖用户文字要求，以三类为准。
- 参考图写着 Key 不同步，但当前用户同时要求 iCloud 同步所有配置；以当前显式需求为准，页面需说明开启 iCloud 时 Key 会同步到私有数据库。

## 当前架构

- 设置导航定义在 `OneBoard/App/OneBoardApp.swift` 的 `SettingsTab` / `SettingsView`。
- 菜单栏菜单每次打开由 `MenuBarManager.makeMainMenu()` 动态生成，适合按 UserDefaults 开关插入日历入口。
- SQLite 由 `DatabaseManager` 初始化；私密 KV 数据使用 `PrivateDataRepository` 的 `private_records` / `application_state`。
- 当前设置大量使用 `@AppStorage` / UserDefaults，同时账号、供应商及密钥等使用 SQLite，不能只同步一个 plist 就声称覆盖全部配置。
- SQLite 配置分布在 `application_state`，敏感配置位于 `private_records`；已确认命名空间含 `application_secret`、AI Provider secret、Codex auth cache，`ai_quota` 是可丢弃快照。
- 主应用 entitlement 由 `Resources/OneBoard.entitlements` 注入，打包脚本对主应用使用该文件签名；CloudKit 能力需在这里声明并在 SwiftPM 链接 CloudKit。
- `MenuBarManager.makeMainMenu()` 每次点击动态生成菜单，因此无需常驻重建监听，直接读取日历开关即可。
- Finder Sync 已用 `oneboard://new-file` 将写操作转交主应用；可增加并行的 `oneboard://open-terminal` 请求复用目标路径解析。
- 当前截图框选工具栏复用 `AnnotationToolbarView`，输出通过 `ScreenshotSelectionAction` 回到 `ScreenshotViewModel`；长截图应新增 action，而不是创建旁路工具栏。
- 当前自定义翻译已复用 `AIProviderStore`、`SQLiteAIProviderSecretVault` 和多协议 `ConfiguredAITranslationService`，重构应保留该能力，避免再造第二套不兼容请求层。

## 工作区状态

- 当前 `main` 相对 `origin/main` ahead 1，且已有大量未提交 UI/截图/Finder/网关改动。
- `OneBoardApp.swift`、`MenuBarManager.swift`、README 与四类文档均已有用户改动，后续只做定点合并，不覆盖或回退。
