# System Capability And Paste Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OneBoard system capability controls reflect real macOS state, fix launch-at-login packaging, add a gateway panel close button, and make clipboard row paste more reliable.

**Architecture:** Add a focused `SystemCapabilityViewModel` that owns only system capability state and actions. Settings UI and menu cleanup refresh through this state layer, while gateway profile switching and clipboard list state remain in their existing view models.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, Swift Package Manager, LaunchAtLogin, macOS TCC via `tccutil`.

---

## File Structure

- Create `OneBoard/Shared/SystemCapabilityViewModel.swift`: Main-actor observable model for accessibility, screen recording, gateway helper, launch-at-login, confirmation, and refresh actions.
- Modify `OneBoard/Shared/PermissionManager.swift`: Add single-permission reset methods and a completion callback from permission guide flow.
- Modify `OneBoard/App/OneBoardApp.swift`: Replace authorization tab local permission state with `SystemCapabilityViewModel`.
- Modify `OneBoard/Shared/MenuBarManager.swift`: Route menu cleanup refresh through the system capability model.
- Modify `OneBoard/Modules/Gateway/ViewModels/GatewayViewModel.swift`: Keep gateway business state, but post status change notifications consistently after helper install and uninstall.
- Modify `OneBoard/Modules/Gateway/Views/GatewaySwitcherPanelView.swift`: Add right-top close button.
- Modify `OneBoard/Modules/Clipboard/ViewModels/ClipboardListViewModel.swift`: Stabilize activation before simulated paste.
- Modify `script/build_app_bundle.sh`: Copy the LaunchAtLogin helper into the app bundle.
- Add or modify `OneBoard/Tests/SystemCapabilityViewModelTests.swift`: Unit-test capability state decisions with injected dependencies.

## Task 1: Add Testable System Capability State Model

**Files:**
- Create: `OneBoard/Shared/SystemCapabilityViewModel.swift`
- Create: `OneBoard/Tests/SystemCapabilityViewModelTests.swift`

- [ ] **Step 1: Write the failing test for refresh and cancel behavior**

Add this test file:

```swift
import XCTest
@testable import OneBoard

@MainActor
final class SystemCapabilityViewModelTests: XCTestCase {
    func testRefreshReadsAllCapabilityStates() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: false)
        let helper = StubGatewayHelperProvider(installed: true)
        let login = StubLaunchAtLoginProvider(enabled: false)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: helper,
            launchAtLogin: login,
            confirmsDisablePermission: { _ in true }
        )

        viewModel.refresh()

        XCTAssertTrue(viewModel.accessibilityGranted)
        XCTAssertFalse(viewModel.screenRecordingGranted)
        XCTAssertTrue(viewModel.gatewayHelperInstalled)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    func testCancelDisableAccessibilityKeepsRealState() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: StubGatewayHelperProvider(installed: false),
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            confirmsDisablePermission: { _ in false }
        )

        viewModel.setAccessibilityEnabled(false)

        XCTAssertTrue(viewModel.accessibilityGranted)
        XCTAssertEqual(permissions.resetServices, [])
    }
}

private final class StubPermissionProvider: SystemPermissionProviding {
    var accessibility: Bool
    var screenRecording: Bool
    var resetServices: [OneBoardPermissionKind] = []

    init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    var hasAccessibilityPermission: Bool { accessibility }
    var hasScreenRecordingPermission: Bool { screenRecording }

    func showPermissionGuide(for kind: OneBoardPermissionKind) {}

    func resetAuthorization(for kind: OneBoardPermissionKind) throws {
        resetServices.append(kind)
        switch kind {
        case .accessibility:
            accessibility = false
        case .screenRecording:
            screenRecording = false
        }
    }
}

private final class StubGatewayHelperProvider: GatewayHelperStatusProviding {
    var installed: Bool

    init(installed: Bool) {
        self.installed = installed
    }

    func isHelperInstalled() -> Bool { installed }
}

private final class StubLaunchAtLoginProvider: LaunchAtLoginProviding {
    var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var isEnabled: Bool {
        get { enabled }
        set { enabled = newValue }
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests
```

Expected: FAIL because `SystemCapabilityViewModel`, `SystemPermissionProviding`, `GatewayHelperStatusProviding`, and `LaunchAtLoginProviding` do not exist.

- [ ] **Step 3: Implement the minimal model and protocols**

Create `OneBoard/Shared/SystemCapabilityViewModel.swift`:

```swift
import Foundation
import LaunchAtLogin

protocol SystemPermissionProviding {
    var hasAccessibilityPermission: Bool { get }
    var hasScreenRecordingPermission: Bool { get }
    func showPermissionGuide(for kind: OneBoardPermissionKind)
    func resetAuthorization(for kind: OneBoardPermissionKind) throws
}

protocol GatewayHelperStatusProviding {
    func isHelperInstalled() -> Bool
}

protocol LaunchAtLoginProviding: AnyObject {
    var isEnabled: Bool { get set }
}

extension PermissionManager: SystemPermissionProviding {
    func showPermissionGuide(for kind: OneBoardPermissionKind) {
        Task { @MainActor in
            PermissionGuideWindowManager.shared.show(for: kind)
        }
    }

    func resetAuthorization(for kind: OneBoardPermissionKind) throws {
        try resetPrivacyAuthorization(for: kind)
    }
}

extension GatewayService: GatewayHelperStatusProviding {}

final class DefaultLaunchAtLoginProvider: LaunchAtLoginProviding {
    var isEnabled: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }
}

@MainActor
final class SystemCapabilityViewModel: ObservableObject {
    static let shared = SystemCapabilityViewModel()

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var gatewayHelperInstalled = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let permissions: SystemPermissionProviding
    private let gatewayHelper: GatewayHelperStatusProviding
    private let launchAtLogin: LaunchAtLoginProviding
    private let confirmsDisablePermission: (OneBoardPermissionKind) -> Bool

    init(
        permissions: SystemPermissionProviding = PermissionManager.shared,
        gatewayHelper: GatewayHelperStatusProviding = GatewayService(),
        launchAtLogin: LaunchAtLoginProviding = DefaultLaunchAtLoginProvider(),
        confirmsDisablePermission: @escaping (OneBoardPermissionKind) -> Bool = SystemCapabilityViewModel.confirmDisablePermission
    ) {
        self.permissions = permissions
        self.gatewayHelper = gatewayHelper
        self.launchAtLogin = launchAtLogin
        self.confirmsDisablePermission = confirmsDisablePermission
        refresh()
    }

    func refresh() {
        accessibilityGranted = permissions.hasAccessibilityPermission
        screenRecordingGranted = permissions.hasScreenRecordingPermission
        gatewayHelperInstalled = gatewayHelper.isHelperInstalled()
        launchAtLoginEnabled = launchAtLogin.isEnabled
        PermissionManager.shared.syncStoredPermissionStates()
    }

    func setAccessibilityEnabled(_ enabled: Bool) {
        setPermission(.accessibility, enabled: enabled)
    }

    func setScreenRecordingEnabled(_ enabled: Bool) {
        setPermission(.screenRecording, enabled: enabled)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLogin.isEnabled = enabled
        launchAtLoginEnabled = launchAtLogin.isEnabled
        if launchAtLoginEnabled != enabled {
            statusMessage = "开机自启未能启用，请确认 OneBoard 已从完整 .app 启动。"
        } else {
            statusMessage = enabled ? "开机自启已启用" : "开机自启已关闭"
        }
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }

    private func setPermission(_ kind: OneBoardPermissionKind, enabled: Bool) {
        if enabled {
            permissions.showPermissionGuide(for: kind)
            refresh()
            return
        }

        guard confirmsDisablePermission(kind) else {
            refresh()
            return
        }

        do {
            try permissions.resetAuthorization(for: kind)
            statusMessage = "\(kind.title)授权已关闭"
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }

    private static func confirmDisablePermission(_ kind: OneBoardPermissionKind) -> Bool {
        let alert = NSAlert()
        alert.messageText = "关闭\(kind.title)授权？"
        alert.informativeText = "OneBoard 将自动撤销该授权。需要重新使用相关功能时，可以再次打开开关并在系统设置中确认。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭授权")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OneBoard/Shared/SystemCapabilityViewModel.swift OneBoard/Tests/SystemCapabilityViewModelTests.swift
git commit -m "feat: add system capability state model"
```

## Task 2: Add Single Permission Reset API

**Files:**
- Modify: `OneBoard/Shared/PermissionManager.swift`
- Modify: `OneBoard/Tests/SystemCapabilityViewModelTests.swift`

- [ ] **Step 1: Add a failing test for confirmed reset**

Append to `SystemCapabilityViewModelTests`:

```swift
func testConfirmDisableAccessibilityResetsOnlyAccessibility() {
    let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
    let viewModel = SystemCapabilityViewModel(
        permissions: permissions,
        gatewayHelper: StubGatewayHelperProvider(installed: false),
        launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
        confirmsDisablePermission: { $0 == .accessibility }
    )

    viewModel.setAccessibilityEnabled(false)

    XCTAssertFalse(viewModel.accessibilityGranted)
    XCTAssertTrue(viewModel.screenRecordingGranted)
    XCTAssertEqual(permissions.resetServices, [.accessibility])
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests/testConfirmDisableAccessibilityResetsOnlyAccessibility
```

Expected: FAIL until single-permission reset compiles and behaves correctly.

- [ ] **Step 3: Implement single-permission reset in `PermissionManager`**

Modify `PermissionManager`:

```swift
func resetPrivacyAuthorization(for kind: OneBoardPermissionKind) throws {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.oneboard.app"
    let service: String
    switch kind {
    case .accessibility:
        service = "Accessibility"
    case .screenRecording:
        service = "ScreenCapture"
    }
    try resetPrivacyAuthorization(service: service, bundleID: bundleID)
    syncStoredPermissionStates()
    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
}
```

Keep `resetPrivacyAuthorizations()` for menu cleanup and make it call the existing two-service path.

- [ ] **Step 4: Run tests**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OneBoard/Shared/PermissionManager.swift OneBoard/Tests/SystemCapabilityViewModelTests.swift
git commit -m "feat: support single permission reset"
```

## Task 3: Wire Settings Authorization Tab To The State Model

**Files:**
- Modify: `OneBoard/App/OneBoardApp.swift`

- [ ] **Step 1: Replace local permission state**

Remove the `@AppStorage` properties for `accessibilityPermissionEnabled` and `screenRecordingPermissionEnabled`, and remove the `@State` permission granted properties. Add:

```swift
@StateObject private var systemCapabilities = SystemCapabilityViewModel.shared
```

- [ ] **Step 2: Replace lifecycle refresh handlers**

Change settings lifecycle handlers to:

```swift
.onAppear {
    systemCapabilities.refresh()
    gatewayViewModel.refreshHelperStatus()
}
.onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
    systemCapabilities.refresh()
}
.onReceive(NotificationCenter.default.publisher(for: .permissionFlowCompleted)) { _ in
    systemCapabilities.refresh()
}
.onReceive(NotificationCenter.default.publisher(for: .systemCapabilityStatusDidChange)) { _ in
    systemCapabilities.refresh()
    gatewayViewModel.refreshHelperStatus()
}
```

- [ ] **Step 3: Replace authorization toggles**

Use real-state bindings:

```swift
permissionToggle(
    title: "辅助功能",
    description: "用于拖拽摇晃唤出暂存区、全局快捷键等交互",
    isOn: Binding(
        get: { systemCapabilities.accessibilityGranted },
        set: { systemCapabilities.setAccessibilityEnabled($0) }
    ),
    isGranted: systemCapabilities.accessibilityGranted
)

permissionToggle(
    title: "屏幕录制",
    description: "用于截图、OCR 和截图翻译",
    isOn: Binding(
        get: { systemCapabilities.screenRecordingGranted },
        set: { systemCapabilities.setScreenRecordingEnabled($0) }
    ),
    isGranted: systemCapabilities.screenRecordingGranted
)
```

Change `permissionToggle` signature to remove `enable` and `disable` closures:

```swift
private func permissionToggle(
    title: String,
    description: String,
    isOn: Binding<Bool>,
    isGranted: Bool
) -> some View
```

Inside it, use `Toggle("", isOn: isOn)`.

- [ ] **Step 4: Replace launch-at-login toggle**

Use:

```swift
Toggle("开机自启", isOn: Binding(
    get: { systemCapabilities.launchAtLoginEnabled },
    set: { systemCapabilities.setLaunchAtLoginEnabled($0) }
))
```

- [ ] **Step 5: Surface status messages**

In the authorization section footer, prefer capability messages:

```swift
if let message = systemCapabilities.errorMessage ?? systemCapabilities.statusMessage ?? gatewayViewModel.statusMessage {
    Text(message)
}
```

- [ ] **Step 6: Build**

Run:

```bash
cd OneBoard && swift build
```

Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
git add OneBoard/App/OneBoardApp.swift
git commit -m "refactor: drive authorization settings from capability state"
```

## Task 4: Refresh Menu Cleanup Through The State Model

**Files:**
- Modify: `OneBoard/Shared/MenuBarManager.swift`

- [ ] **Step 1: Update cleanup refresh path**

After privacy reset, helper uninstall, and launch-at-login changes, refresh both models on the main actor:

```swift
Task { @MainActor in
    SystemCapabilityViewModel.shared.refresh()
    GatewayViewModel.shared.refreshHelperStatus()
    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
}
```

- [ ] **Step 2: Keep cleanup behavior unchanged**

Confirm these branches still exist:

```swift
if choice == .alertSecondButtonReturn {
    do {
        try OneBoardGatewayHelper().uninstall()
    } catch {
        failures.append("网关 Helper 卸载失败：\(error.localizedDescription)")
    }
    LaunchAtLogin.isEnabled = false
    UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.launchAtLogin)
}
```

- [ ] **Step 3: Build**

Run:

```bash
cd OneBoard && swift build
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add OneBoard/Shared/MenuBarManager.swift
git commit -m "fix: refresh capability state after clearing authorizations"
```

## Task 5: Package LaunchAtLogin Helper

**Files:**
- Modify: `script/build_app_bundle.sh`

- [ ] **Step 1: Add helper copy logic**

After creating `RESOURCES_DIR`, define:

```bash
LOGIN_ITEMS_DIR="$CONTENTS_DIR/Library/LoginItems"
```

After copying resources, add:

```bash
mkdir -p "$LOGIN_ITEMS_DIR"
HELPER_ZIP="$PROJECT_DIR/.build/checkouts/LaunchAtLogin/Sources/LaunchAtLogin/LaunchAtLoginHelper.zip"
HELPER_APP="$LOGIN_ITEMS_DIR/LaunchAtLoginHelper.app"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$CONTENTS_DIR/Info.plist")"

if [ -f "$HELPER_ZIP" ]; then
    rm -rf "$HELPER_APP"
    unzip -q "$HELPER_ZIP" -d "$LOGIN_ITEMS_DIR"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_ID}-LaunchAtLoginHelper" "$HELPER_APP/Contents/Info.plist"
else
    echo "Missing LaunchAtLogin helper zip: $HELPER_ZIP" >&2
    exit 1
fi
```

Current expected helper bundle ID is `com.oneboard.app-LaunchAtLoginHelper`.

- [ ] **Step 2: Run package build**

Run:

```bash
script/build_app_bundle.sh
```

Expected: `build/OneBoard.app` exists.

- [ ] **Step 3: Verify helper location**

Run:

```bash
test -d build/OneBoard.app/Contents/Library/LoginItems/LaunchAtLoginHelper.app
```

Expected: command exits with status 0.

- [ ] **Step 4: Verify helper bundle ID**

Run:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" build/OneBoard.app/Contents/Library/LoginItems/LaunchAtLoginHelper.app/Contents/Info.plist
```

Expected: prints `com.oneboard.app-LaunchAtLoginHelper` or the actual OneBoard bundle ID followed by `-LaunchAtLoginHelper`.

- [ ] **Step 5: Commit**

```bash
git add script/build_app_bundle.sh
git commit -m "fix: package launch at login helper"
```

## Task 6: Add Gateway Panel Close Button

**Files:**
- Modify: `OneBoard/Modules/Gateway/Views/GatewaySwitcherPanelView.swift`

- [ ] **Step 1: Add close button next to refresh**

Change the header trailing controls to:

```swift
HStack(spacing: 8) {
    Button {
        viewModel.refresh()
    } label: {
        Image(systemName: "arrow.clockwise")
    }
    .disabled(viewModel.isRefreshing)
    .help("刷新")

    Button {
        MenuBarManager.shared.closeGatewaySwitcherPanel()
    } label: {
        Image(systemName: "xmark")
    }
    .help("关闭")
}
```

- [ ] **Step 2: Build**

Run:

```bash
cd OneBoard && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneBoard/Modules/Gateway/Views/GatewaySwitcherPanelView.swift
git commit -m "feat: add gateway panel close button"
```

## Task 7: Stabilize Clipboard Auto Paste Timing

**Files:**
- Modify: `OneBoard/Modules/Clipboard/ViewModels/ClipboardListViewModel.swift`

- [ ] **Step 1: Extract activation wait helper**

Add this helper near `simulatePaste()`:

```swift
private func activateAndPaste(into app: NSRunningApplication?) {
    guard let app else {
        print("[ViewModel] ⚠️ 找不到目标应用，已只写入剪贴板")
        PasteboardMonitor.shared.isPasting = false
        return
    }

    app.activate(options: [.activateIgnoringOtherApps])
    waitForActivation(app, remainingAttempts: 8)
}

private func waitForActivation(_ app: NSRunningApplication, remainingAttempts: Int) {
    guard remainingAttempts > 0 else {
        print("[ViewModel] ⚠️ 目标应用未及时激活，尝试发送粘贴快捷键")
        simulatePaste()
        PasteboardMonitor.shared.isPasting = false
        return
    }

    if app.isActive {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.simulatePaste()
            PasteboardMonitor.shared.isPasting = false
        }
        return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        self?.waitForActivation(app, remainingAttempts: remainingAttempts - 1)
    }
}
```

- [ ] **Step 2: Use helper in `selectAndPaste`**

Replace the fixed-delay paste block with:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
    self?.activateAndPaste(into: previousApp)
}
```

- [ ] **Step 3: Keep paste monitor reset on missing permission**

In `simulatePaste()`, before returning for missing accessibility permission, add:

```swift
PasteboardMonitor.shared.isPasting = false
```

- [ ] **Step 4: Build**

Run:

```bash
cd OneBoard && swift build
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add OneBoard/Modules/Clipboard/ViewModels/ClipboardListViewModel.swift
git commit -m "fix: wait for target app before clipboard paste"
```

## Task 8: Final Verification And Development Log

**Files:**
- Modify: `开发日志/2026-06/2026-06-15.md`

- [ ] **Step 1: Run all tests**

Run:

```bash
cd OneBoard && swift test
```

Expected: All tests pass.

- [ ] **Step 2: Run build**

Run:

```bash
cd OneBoard && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Run bundle script**

Run:

```bash
script/build_app_bundle.sh
```

Expected: `build/OneBoard.app` exists and contains `Contents/Library/LoginItems/LaunchAtLoginHelper.app`.

- [ ] **Step 4: Update development log**

Append:

```markdown

## 系统能力联动与粘贴稳定性

- [x] 新增系统能力状态层，统一刷新辅助功能、屏幕录制、网关 Helper 和开机自启状态。
- [x] 关闭隐私权限时增加确认框，并在确认后自动撤销对应授权。
- [x] 修复 LaunchAtLogin helper 未打包导致开机自启开关弹回的问题。
- [x] 网关切换弹窗增加右上角关闭按钮。
- [x] 优化剪贴板点击条目后的目标 App 激活与自动粘贴时序。

## 验证

- [x] `cd OneBoard && swift test`
- [x] `cd OneBoard && swift build`
- [x] `script/build_app_bundle.sh`
```

- [ ] **Step 5: Commit**

```bash
git add 开发日志/2026-06/2026-06-15.md
git commit -m "docs: update development log for capability fixes"
```

## Self-Review

- Spec coverage: Tasks 1-4 cover unified capability state, permission disable confirmation, and cleanup refresh; Task 5 covers launch-at-login packaging; Task 6 covers gateway close button; Task 7 covers clipboard auto paste reliability; Task 8 covers verification and development log.
- Placeholder scan: No placeholder markers remain.
- Type consistency: `SystemCapabilityViewModel`, provider protocols, and method names are introduced in Task 1 and reused consistently in later tasks.
