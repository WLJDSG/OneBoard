# 方案：授权逻辑重新设计

**日期**：2026-06-27 | **版本**：v1.0

---

## 一、当前问题总结

当前授权逻辑有 15 个问题，核心矛盾：

1. **开关反弹**：用户开 → 弹引导 → `refresh()` 发现还是关 → 开关弹回关 → 1.5s 后变开。用户困惑。
2. **死代码**：4 个 UserDefaults key 写入但从不读取。
3. **通知权限检查不一致**（`PermissionManager` vs `TodoReminderService`）
4. **滥用定时器**：Settings 页每秒刷新 4 个系统 API
5. **关闭权限流程可能卡死**
6. **拖动授权图标没用**（功能不完整）

---

## 二、新设计：按钮式权限管理

### 设计原则

1. **状态和操作分离**：状态是状态（已授权/未授权），操作是操作（点击按钮去授权）
2. **不自动弹回**：无开关 = 无反弹
3. **异步友好**：用 async/await 替代定时器轮询
4. **死代码清理**：删除从不读取的 UserDefaults key

### 新 UI 设计

```
设置 → 授权
┌─────────────────────────────────────────────────────────┐
│  隐私权限                                                │
│                                                         │
│  🔒 辅助功能                     [未授权] [去开启 →]    │
│     用于自动粘贴、读取选中文字、全局交互                  │
│                                                         │
│  🖥️ 屏幕录制                    [已授权 ✓]              │
│     用于截图、OCR 和截图翻译                             │
│                                                         │
│  ⌨️ 输入监控                     [未授权] [去开启 →]    │
│     用于文件拖拽摇晃检测等全局输入监听                    │
│                                                         │
│  🔔 通知                         [未授权] [去开启 →]    │
│     用于待办事项到期提醒                                  │
│─────────────────────────────────────────────────────────│
│  系统能力                                                │
│                                                         │
│  🔑 网关免密 Helper               [已安装] [卸载...]    │
│     用于网关切换时避免反复输入管理员密码                  │
│                                                         │
│  🚀 开机自启                        [已开启]  [开关]    │
└─────────────────────────────────────────────────────────┘
```

### 交互流程

```
用户看到 [未授权] [去开启 →]
         │
         ├─ 点击「去开启」
         │   ├─ 系统设置自动打开到对应隐私面板
         │   ├─ 浮动引导小窗弹出（告诉用户怎么做）
         │   └─ 按钮变为 [请求中...]（带 spinner）
         │
         ├─ 用户在系统设置中开启权限
         │   ├─ App 检测到权限已获取
         │   ├─ 引导窗自动关闭
         │   ├─ 状态变为 [已授权 ✓]
         │   └─ 按钮消失
         │
         └─ 用户关闭引导窗 / 未开启权限
             ├─ 状态保持 [未授权]
             └─ 按钮恢复 [去开启 →]
```

### 与旧版对比

| 方面 | 旧版 | 新版 |
|------|------|------|
| UI 控件 | Toggle 开关（开关弹回） | 按钮（无反弹） |
| 状态显示 | "已授权"/"未授权" + 小图标 | 大号状态标签 + 操作按钮 |
| 已授权态 | 开关 ON（可关闭） | **[已授权 ✓]** 只读标签 + [撤销] 小按钮 |
| 未授权态 | 开关 OFF（可打开 → 弹回） | **[未授权]** 标签 + **[去开启 →]** 按钮 |
| 操作中态 | 无视觉反馈 | **[请求中...]** + spinner |
| 关闭权限 | 确认弹窗 → tccutil reset | [撤销] 按钮 → 确认弹窗 → tccutil reset |
| 轮询 | 0.5s 定时器 | 0.5s 定时器（不变，但仅在有 active flow 时启动） |
| Settings 定时器 | 1s 全局刷新 | 按需刷新（收到通知时）+ 10s 降级轮询 |

---

## 三、代码改动计划

### 3.1 `SystemCapabilityViewModel` 重构

```
当前：
  @Published var accessibilityGranted: Bool       // 仅 bool
  @Published var screenRecordingGranted: Bool
  @Published var inputMonitoringGranted: Bool
  @Published var notificationGranted: Bool
  @Published var errorMessage: String?            // 混用
  @Published var statusMessage: String?
  @Published var activePermissionOperation: PermissionKind?  // 未使用

改为：
  enum PermissionState {
      case authorized
      case notAuthorized
      case requesting          // 正在请求中
  }

  @Published var accessibilityState: PermissionState
  @Published var screenRecordingState: PermissionState
  @Published var inputMonitoringState: PermissionState
  @Published var notificationState: PermissionState
```

### 3.2 Settings UI 改动 (`OneBoardApp.swift`)

- 删除 `permissionToggle()` helper（Toggle 版本）
- 新增 `permissionRow()` helper（按钮版本）
- 删除 `capabilityToggle()` helper → 改为统一 `permissionRow()`
- 删除 1 秒定时器 → 改为 `.onReceive(NotificationCenter...)` 懒刷新

### 3.3 `PermissionManager` 清理

- 删除 `syncStoredPermissionStates()` 中写入 4 个死 UserDefaults key 的代码
- 删除 `AppDelegate.setupDefaultSettings()` 中初始化这 4 个 key 的代码
- 删除 `Constants.swift` 中对应的 key 定义
- 修复 `TodoReminderService.hasPermission` 接受 `.provisional`

### 3.4 `PermissionGuideWindowManager` 改进

- 关闭按钮改为「取消」按钮（更清晰）
- 用户手动关闭引导窗时，`SystemCapabilityViewModel` 的 state 恢复为 `.notAuthorized`

---

## 四、改动文件清单

| 文件 | 改动量 | 说明 |
|------|--------|------|
| `SystemCapabilityViewModel.swift` | 大改 | 重新设计 ViewModel |
| `OneBoardApp.swift` | 中改 | Settings UI 重写 |
| `PermissionManager.swift` | 小改 | 删除死代码 |
| `PermissionGuideWindowManager.swift` | 小改 | 改进引导窗交互 |
| `Constants.swift` | 小改 | 删除死 key |
| `AppDelegate.swift` | 小改 | 删除死 key 初始化 |
| `TodoReminderService.swift` | 小改 | 修复 `.provisional` |
