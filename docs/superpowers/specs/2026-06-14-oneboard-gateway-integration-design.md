# OneBoard 网关切换集成设计

日期：2026-06-14

## 背景

OneBoard 目前定位为 macOS 菜单栏效率工具，已包含截图、历史剪贴板、文件暂存和设置能力。另有独立项目 `gateway-switch`，用于在 macOS 上切换当前网络服务的默认网关和 DNS。

本次设计目标是将 `gateway-switch` 完全并入 OneBoard，让 OneBoard 成为唯一入口。独立 `gateway-switch` App、Widget 和 URL Scheme 不在第一版迁移范围内。

## 目标

1. 在 OneBoard 内新增网关切换模块，支持查看当前网络状态、管理网关 Profile、一键切换网关和 DNS。
2. 支持 Profile 的两种切换模式：`网关 + DNS` 和 `仅 DNS`。
3. 支持 OneBoard 专属免密 helper，避免每次切换都弹管理员授权。
4. 支持全局快捷键唤出网关切换小窗，默认 `Command + Shift + G`，并可在设置中修改或清空。
5. 重构设置页的系统能力管理，将辅助功能、屏幕录制、网关免密 Helper、开机自启放入独立“授权”页面。
6. 修复现有权限开关和文案不同步问题，确保清除授权、关闭权限、helper 安装/卸载、开机自启状态都能及时联动。
7. 菜单项“清除隐私授权...”升级为“清除 OneBoard 授权...”，支持仅清隐私权限或清除全部系统授权。

## 非目标

1. 不迁移旧 `gateway-switch` 的 UserDefaults/App Group 配置。
2. 不并入 `gateway-switch` Widget。
3. 不并入 `gatewayswitcher://` URL Scheme。
4. 不删除用户普通配置数据，例如剪贴板保留策略、OCR/翻译配置、网关 Profile。
5. 不新增 Profile 指定网络服务能力。第一版始终自动使用当前默认路由所在网络服务。

## 模块结构

新增目录：

```text
OneBoard/Modules/Gateway/
├── Models/
├── Services/
├── ViewModels/
└── Views/
```

建议核心类型：

- `GatewayProfile`：网关配置项，包含标题、模式、网关 IP、DNS 列表、描述和 SF Symbol 名称。
- `GatewaySwitchMode`：`gatewayAndDNS` 或 `dnsOnly`。
- `NetworkSnapshot`：当前默认网关、网络服务、接口、本机 IPv4、子网掩码、DNS 和更新时间。
- `GatewayError`：网关切换、配置校验、helper 操作中的错误。
- `GatewayProfileStore`：OneBoard 自己的 Profile 持久化。
- `NetworkInspector`：读取当前默认路由、网络服务、本机 IP、子网掩码和 DNS。
- `GatewaySwitcher`：执行切换命令。
- `GatewayService`：编排刷新、切换、helper 状态和白名单同步。
- `GatewayViewModel`：小窗和设置页共享的主状态。
- `GatewayProfileEditorViewModel`：新增/编辑表单逻辑。

## 数据设计

网关 Profile 属于设置型数据，第一版使用 OneBoard 自己的 `UserDefaults` JSON 存储，不进入 SQLite，也不读取旧 `gateway-switch` App Group。

新增 `Constants.UserDefaultsKeys.gatewayProfiles`，保存 `[GatewayProfile]` 编码后的数据。

默认初始化三条 Profile：

| 标题 | 模式 | 网关 | DNS | 图标 |
| --- | --- | --- | --- | --- |
| 国内网关 | 网关 + DNS | `192.168.31.1` | `192.168.31.1` | `router` |
| `.2 网关` | 网关 + DNS | `192.168.31.2` | `192.168.31.2` | `point.3.connected.trianglepath.dotted` |
| 代理网关 | 网关 + DNS | `192.168.31.3` | `192.168.31.3` | `network.badge.shield.half.filled` |

Profile 校验规则：

- `网关 + DNS` 模式必须填写合法 IPv4 网关。
- `仅 DNS` 模式不要求网关。
- DNS 支持多个 IPv4，输入时允许逗号、空格或换行分隔。
- DNS 列表不能为空。
- 标题不能为空。

## 网络切换行为

网络服务选择策略：

- 始终检测当前默认路由对应的接口。
- 通过 `networksetup -listallhardwareports` 将接口映射为服务名，例如 `Wi-Fi` 或有线网络服务。
- 切换时只写入这个当前默认路由所在服务。

`网关 + DNS` 模式：

1. 读取当前服务名、本机 IP 和子网掩码。
2. 优先调用 OneBoard 免密 helper。
3. helper 不可用时回退到 `osascript ... with administrator privileges`。
4. 执行：
   - `networksetup -setmanual <service> <ip> <subnet> <gateway>`
   - `networksetup -setdnsservers <service> <dns...>`
   - `route -n change default <gateway>`，失败后尝试 `route -n add default <gateway>`
   - 刷新 DNS 缓存。

`仅 DNS` 模式：

1. 读取当前服务名。
2. 优先调用 OneBoard 免密 helper。
3. helper 不可用时回退到管理员授权。
4. 执行：
   - `networksetup -setdnsservers <service> <dns...>`
   - 刷新 DNS 缓存。
5. 不修改默认网关和路由。

## OneBoard 免密 Helper

helper 从 `gateway-switcher` 命名迁移为 OneBoard 专属命名：

- helper：`/usr/local/bin/oneboard-gateway-helper`
- sudoers：`/etc/sudoers.d/oneboard-gateway`
- 白名单：`/etc/oneboard-gateway-allowed-ips.conf`

helper 能力：

- 支持 `网关 + DNS`。
- 支持 `仅 DNS`。
- 校验服务名、网关和 DNS 是否在白名单内。
- Profile 变更后同步刷新白名单。

设置页“授权”页面提供网关 Helper 独立开关：

- 打开：安装 OneBoard helper、sudoers 规则和白名单。
- 关闭：卸载 helper、删除 sudoers 规则和白名单。
- 安装或卸载失败时显示具体失败信息。

## UI 与入口

### 菜单栏

OneBoard 主菜单保持轻量，只新增：

- `网关切换...`

原有菜单项保留并调整：

- `设置...`
- `清除 OneBoard 授权...`
- `退出 OneBoard`

`清除 OneBoard 授权...` 补充 SF Symbol 图标 `lock.slash`。现有 `清除隐私授权...` 文案不再使用。

### 网关切换小窗

点击 `网关切换...` 或按下默认快捷键 `Command + Shift + G` 打开专用小窗。再次触发快捷键时关闭小窗。

小窗内容：

- 顶部显示当前 Profile 或当前网关。
- 显示当前网络服务、本机 IP、接口和 DNS。
- Profile 列表显示标题、模式、网关/DNS 摘要、图标。
- 当前命中的 Profile 显示已选中状态。
- 点击 Profile 行执行切换。
- 切换中禁用重复点击，并显示状态文案。
- 提供刷新按钮。
- 提供设置按钮，打开 OneBoard 设置窗口并定位到“网关”Tab。
- 点击外部或应用失焦后关闭，行为接近剪贴板浮动窗。

### 设置页

设置页 Tab 调整为：

1. `通用`
2. `授权`
3. `快捷键`
4. `网关`
5. `识别·翻译`
6. `关于`

`通用` 页面只保留普通偏好设置，例如剪贴板最大记录条数和保留天数。

`授权` 页面集中放系统能力开关：

- 辅助功能：打开时进入授权引导，关闭时进入撤销引导。
- 屏幕录制：打开时进入授权引导，关闭时进入撤销引导。
- 网关免密 Helper：打开安装 helper，关闭卸载 helper。
- 开机自启：打开/关闭 `LaunchAtLogin.isEnabled`。

`快捷键` 页面新增：

- `显示网关切换`，默认 `Command + Shift + G`，可修改或清空。

`网关` 页面：

- 当前网络状态详情。
- Profile 列表。
- 新增、编辑、删除、刷新、切换操作。
- 编辑表单包含标题、图标、模式、网关 IP、DNS、描述。

## 授权清理设计

菜单项 `清除 OneBoard 授权...` 点击后弹出确认框，提供三个按钮：

1. `仅清除隐私权限`
2. `清除全部授权`
3. `取消`

`仅清除隐私权限`：

- 清除辅助功能授权。
- 清除屏幕录制授权。
- 不动网关 helper。
- 不动开机自启。

`清除全部授权`：

- 清除辅助功能授权。
- 清除屏幕录制授权。
- 卸载 OneBoard 网关 helper。
- 删除 helper sudoers 规则。
- 删除 helper 白名单文件。
- 关闭开机自启。

卸载 helper、删除 sudoers 和删除白名单属于系统路径操作，需要管理员授权。授权失败或用户取消时不应影响已成功清除的其他项目，但结果提示必须列出失败项。

清理完成后：

- 发送统一的系统能力状态刷新通知。
- 设置页“授权”页面立即刷新所有开关和文案。
- 网关页面刷新 helper 状态。
- 如部分清理失败，提示失败项和原因。

## 权限状态同步修正

现有权限开关不同步的问题要作为本次范围的一部分修复。

设计要求：

- 真实状态以 `PermissionManager`、helper 安装检测和 `LaunchAtLogin.isEnabled` 为准。
- 增加统一通知，例如 `systemCapabilityStatusDidChange`。
- 清除授权、授权流程完成、撤销流程完成、helper 安装/卸载、开机自启切换后都发送通知。
- `SettingsView` 收到通知后同步刷新 `@State` 和 `@AppStorage`。
- 清除隐私权限成功后立即将辅助功能和屏幕录制对应存储值同步为真实状态，通常为 `false`。
- 撤销流程完成后同样刷新文案，不依赖下一次定时器。
- 设置页打开时仍保留定时同步作为兜底。

## 错误处理

小窗和设置页都应显示清晰错误：

- 未检测到默认路由。
- 未检测到可写入网络服务。
- 未检测到本机 IP 或子网掩码。
- 网关或 DNS IP 不合法。
- 用户取消管理员授权。
- helper 未安装或不可用。
- helper 白名单不同步。
- helper 安装或卸载失败。
- `networksetup` 或 `route` 命令失败。

错误不应导致小窗关闭，用户可以刷新或重试。

## 测试与验证

新增或迁移测试：

- Profile 默认初始化。
- Profile 校验：标题、模式、网关、多个 DNS。
- DNS 输入解析：逗号、空格、换行。
- route 和 networksetup 输出解析。
- `网关 + DNS` 命令生成。
- `仅 DNS` 命令生成。
- helper 路径、sudoers 路径、白名单路径。
- helper 白名单同步和卸载路径。
- `GatewayViewModel` 刷新、切换、防重复点击、错误文案。
- 权限状态刷新：清除隐私权限后状态归零。
- 清除全部授权：helper 状态归零，开机自启关闭。
- 快捷键注册：`showGatewaySwitcher` 存在默认值且可录制修改。

实现完成后必须执行：

```bash
cd OneBoard && swift build
```

如测试环境允许，再执行相关 Swift test target。

## 实施顺序建议

1. 迁移纯模型、ProfileStore、解析器和命令 runner 测试。
2. 实现 OneBoard 命名的 helper 安装、卸载和白名单同步。
3. 实现 `GatewayService` 与 `GatewayViewModel`。
4. 添加设置页“授权”页面，修复系统能力状态同步。
5. 添加设置页“网关”页面和编辑表单。
6. 添加网关切换小窗、菜单入口和快捷键。
7. 改造“清除 OneBoard 授权...”弹窗和执行路径。
8. 运行构建和测试，更新开发日志与开发步骤。
