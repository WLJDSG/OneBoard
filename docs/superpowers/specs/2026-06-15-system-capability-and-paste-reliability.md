# OneBoard 系统能力联动与粘贴稳定性设计

日期：2026-06-15

## 背景

当前设置页“授权”区域、菜单“清除 OneBoard 授权”、网关免密 Helper、开机自启和剪贴板点击粘贴存在状态不同步或偶发失败问题。用户已确认采用方案 3：新增统一的系统能力状态层，集中管理系统能力真实状态和动作，避免设置页开关、状态标签、菜单清理结果各自维护状态。

## 目标

1. 授权页的辅助功能、屏幕录制开关和“已授权/未授权”标签始终跟随 macOS 真实权限状态。
2. 关闭辅助功能或屏幕录制开关时弹确认框；确认后自动撤销 OneBoard 对应授权，取消则恢复真实状态。
3. 修复开机自启开关点击后立即弹回的问题。
4. 网关切换弹窗右上角提供关闭按钮。
5. 菜单“清除 OneBoard 授权...”完成后，设置页立即刷新辅助功能、屏幕录制、网关 Helper、开机自启四类状态。
6. 剪贴板点击某一行后，目标 App 已有正确剪贴板内容但未自动粘贴的问题，需要通过更稳定的激活和 Cmd+V 时序修复。

## 非目标

1. 不自动静默新增辅助功能或屏幕录制授权。macOS 不允许 App 或 helper 合法可靠地绕过 TCC 用户确认。
2. 不让系统能力状态层接管网关 Profile、网关列表切换、剪贴板列表等业务状态。
3. 不迁移或删除普通用户配置、网关 Profile、剪贴板历史。

## 设计

### SystemCapabilityViewModel

新增统一状态层，集中暴露：

- `accessibilityGranted`
- `screenRecordingGranted`
- `gatewayHelperInstalled`
- `launchAtLoginEnabled`
- `statusMessage`
- `errorMessage`

该 ViewModel 负责：

- 从 `PermissionManager`、`GatewayService` 和 `LaunchAtLogin` 读取真实状态。
- 设置页出现、App 激活、权限引导完成、Helper 安装/卸载、菜单清理完成后统一刷新。
- 执行辅助功能和屏幕录制的开启引导、关闭确认和自动撤销。
- 执行开机自启开关写入后读回真实状态。
- 提供菜单清除授权后的统一刷新入口。

设置页授权 Tab 不再直接使用 `@AppStorage` 维护辅助功能和屏幕录制开关状态。`UserDefaults` 可继续作为兼容缓存，但 UI 不以它作为真实状态源。

### 权限开启和关闭

开启辅助功能或屏幕录制：

1. 保持现有行为，打开对应系统设置页。
2. 显示引导浮窗。
3. 轮询真实授权状态。
4. 授权完成后刷新 ViewModel 状态。

关闭辅助功能或屏幕录制：

1. 弹出确认框。
2. 用户取消时不执行撤销，并刷新回真实状态。
3. 用户确认时调用 `tccutil reset <service> <bundleID>` 只撤销对应权限。
4. 撤销后刷新状态并发送系统能力状态变化通知。

### 开机自启

当前手动打包脚本只拷贝主程序和资源，没有把 `LaunchAtLoginHelper.app` 放进 `OneBoard.app/Contents/Library/LoginItems/`。需要在打包脚本中补齐 LaunchAtLogin helper，并设置 helper Bundle ID 为：

```text
<OneBoard Bundle ID>-LaunchAtLoginHelper
```

设置页切换开机自启后应读回 `LaunchAtLogin.isEnabled` 作为最终状态。如果写入失败或读回不一致，显示状态提示。

### 网关弹窗关闭按钮

`GatewaySwitcherPanelView` 右上角新增 `xmark` 图标按钮。点击后调用现有 `MenuBarManager.shared.closeGatewaySwitcherPanel()`。保留现有刷新按钮。

### 清除 OneBoard 授权

菜单清除动作完成后：

- “仅清除隐私权限”：辅助功能和屏幕录制刷新为未授权；网关 Helper 和开机自启保持真实状态。
- “清除全部授权”：辅助功能、屏幕录制、网关 Helper、开机自启全部刷新为关闭或未启用。

所有结果通过 `SystemCapabilityViewModel` 或统一通知刷新设置页。

### 剪贴板点击粘贴

剪贴板写入已验证成功，失败点在目标 App 激活和 Cmd+V 时序。改进方向：

1. 保留打开剪贴板前捕获的目标 App。
2. 写入剪贴板后关闭 OneBoard 浮窗。
3. 激活目标 App。
4. 等待目标 App 成为 active，或使用更稳妥的短轮询/延迟。
5. 再发送 Cmd+V。
6. 无辅助功能权限或找不到目标 App 时给出明确日志和状态提示。

## 测试与验证

1. `swift build` 必须通过。
2. 设置页授权 Tab：
   - 已授权状态下开关和标签一致。
   - 关闭开关弹确认框。
   - 取消后状态恢复。
   - 确认后对应权限变为未授权。
3. 开机自启：
   - 打包后的 `.app` 内存在 `Contents/Library/LoginItems/LaunchAtLoginHelper.app`。
   - 点击开关不会立即弹回。
4. 菜单“清除 OneBoard 授权...”：
   - 两种清理模式后设置页状态立即刷新。
5. 网关弹窗：
   - 右上角关闭按钮可关闭弹窗。
6. 剪贴板：
   - 点击文本条目后，目标 App 自动获得焦点并粘贴选中内容。
