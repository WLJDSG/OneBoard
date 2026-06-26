# Bug 修复方案：截图闪退 + 菜单栏图标偏位

**日期**：2026-06-27 | **版本**：v1.0

---

## 一、截图闪退修复

### 根因

| # | 位置 | 问题 | 严重度 |
|---|------|------|--------|
| 1 | `ScreenshotViewModel.swift:411,419` | `as! AXUIElement` 强制转换 CFTypeRef → 非 AX 类型时崩溃 | 🔴 高 |
| 2 | `ScreenshotViewModel.swift:182` | `MainActor.assumeIsolated` 在 KVO 回调中 → 非主线程回调崩溃 | 🔴 高 |
| 3 | `ScreenshotCaptureService.swift:22-30` | `continuation` 可能永不 resume → 挂死 | 🟡 中 |

### 修复方案

**修复 1：`as!` → `guard let as?`**

```swift
// Before (ScreenshotViewModel.swift:411):
AXUIElementCopyAttributeValue(app as! AXUIElement, ...)

// After:
guard let axApp = app as? AXUIElement else {
    continuation.resume(returning: nil)
    return
}
AXUIElementCopyAttributeValue(axApp, ...)
```

同样处理 line 419 的 `element as! AXUIElement`。

**修复 2：`MainActor.assumeIsolated` → `Task { @MainActor in }`**

```swift
// Before (ScreenshotViewModel.swift:182):
MainActor.assumeIsolated { ... }

// After:
Task { @MainActor [weak self] in
    guard let self, let toolbar = self.toolbarPanel else { return }
    ...
}
```

**修复 3：添加 continuation resume 保护**

```swift
// ScreenshotCaptureService.swift:
// 确保 deinit 时 resume continuation
deinit {
    pendingContinuation?.resume(returning: nil)
    pendingContinuation = nil
}
```

### 改动范围
- `ScreenshotViewModel.swift`：3 处修复
- `ScreenshotCaptureService.swift`：1 处修复

---

## 二、菜单栏图标偏位修复

### 根因

1. **SF Symbol 替代了手绘图标**（commit `0d26e4d`）：SF Symbol `"square.on.square"` 自带 typographic baseline 偏移
2. **创建时序错误**：`main.swift` 用 `variableLength` 创建 → `MenuBarManager` 设 image → 再改成 `squareLength`，中间布局未重排

### 修复方案

**修复 1：main.swift 直接使用 `squareLength`**

```swift
// Before (main.swift:9):
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

// After:
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
```

**修复 2：MenuBarManager 删除冗余的 length 设置**

删除 `configure(statusItem:)` 中的 `statusItem.length = NSStatusItem.squareLength`（line 41），因为 main.swift 已经设置。

**修复 3：恢复手绘图标或校正 SF Symbol 偏移**

方案 A（推荐）：恢复原来的 NSBezierPath 手绘图标（从 commit `0d26e4d` 提取代码），精确控制位置。

方案 B：保留 SF Symbol，使用 `.withSymbolConfiguration` 控制尺寸，并设置 `button.imagePosition = .imageOnly` + `button.imageAlignment = .alignCenter`（目前只设了 `imagePosition`）。

### 改动范围
- `main.swift`：1 处修改
- `MenuBarManager.swift`：删除 1 行 + 修改 `createMenuBarIcon()`
