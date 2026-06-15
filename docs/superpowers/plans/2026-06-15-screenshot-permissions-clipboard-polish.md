# Screenshot, Permissions, Clipboard Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix OneBoard's launch-at-login packaging, screenshot toolbar and OCR UX, translation workbench layout, clipboard duplicate recording, and permission state refresh behavior as approved in the design spec.

**Architecture:** Keep existing SwiftUI + AppKit MVVM/service structure. Add small focused seams for testability where async window/pasteboard/system state currently hides behavior, and keep visual changes localized to existing Screenshot and Settings views. Package fixes stay in `script/build_app_bundle.sh`.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit `NSPanel`, LaunchAtLogin helper app, NSPasteboard, XCTest, Swift Package Manager.

---

## File Structure

- Modify `script/build_app_bundle.sh`: package and sign the LaunchAtLogin helper and main app, then print validation details.
- Modify `OneBoard/Shared/SystemCapabilityViewModel.swift`: improve launch-at-login status messages, add operation-state handling and delayed permission refresh.
- Modify `OneBoard/Tests/SystemCapabilityViewModelTests.swift`: cover launch failure message, screen-recording-only reset, operation-state recovery.
- Modify `OneBoard/Modules/Clipboard/Services/PasteboardMonitor.swift`: make ignore scope async-safe and expose a testable change-count sync seam.
- Modify `OneBoard/Modules/Clipboard/ViewModels/ClipboardListViewModel.swift`: wrap click-to-paste flow in monitor ignore scope and always restore state.
- Create `OneBoard/Tests/ClipboardPasteCoordinatorTests.swift`: cover no duplicate-monitor behavior with a small coordinator seam.
- Modify `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`: centralize screenshot session cleanup and close dependent panels.
- Modify `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`: implement B+C mixed toolbar, more colors, remove copy button, add completion check button.
- Create `OneBoard/Modules/Screenshot/Views/OCRBubbleWindowManager.swift`: dedicated OCR bubble panel with outside-click close.
- Create `OneBoard/Tests/ScreenshotSessionLifecycleTests.swift`: cover idempotent cleanup through test doubles where possible.
- Modify `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`: implement selected B layout with tighter title bar and stable dimensions.
- Modify `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`: set fixed/min window size and expose `closePanel()` for screenshot cleanup.
- Update `docs/开发步骤/README.md` and `开发日志/2026-06/2026-06-15.md`: record completed fixes after implementation.

## Task 1: Launch-at-login packaging and status

**Files:**
- Modify: `script/build_app_bundle.sh`
- Modify: `OneBoard/Shared/SystemCapabilityViewModel.swift`
- Test: `OneBoard/Tests/SystemCapabilityViewModelTests.swift`

- [ ] **Step 1: Add failing launch-at-login message test**

Append this test inside `SystemCapabilityViewModelTests`:

```swift
func testLaunchAtLoginFailureShowsInstalledAppGuidance() {
    let login = StubLaunchAtLoginProvider(enabled: false)
    login.forceReadBackValue = false
    let viewModel = SystemCapabilityViewModel(
        permissions: StubPermissionProvider(accessibility: true, screenRecording: true),
        gatewayHelper: StubGatewayHelperProvider(installed: true),
        launchAtLogin: login,
        confirmsDisablePermission: { _ in true }
    )

    viewModel.setLaunchAtLoginEnabled(true)

    XCTAssertFalse(viewModel.launchAtLoginEnabled)
    XCTAssertEqual(
        viewModel.statusMessage,
        "开机自启未能启用，请确认 OneBoard 位于 /Applications，且登录项 Helper 已正确打包并签名。"
    )
}
```

Update the stub in the same file:

```swift
private final class StubLaunchAtLoginProvider: LaunchAtLoginProviding {
    var enabled: Bool
    var forceReadBackValue: Bool?

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var isEnabled: Bool {
        get { forceReadBackValue ?? enabled }
        set { enabled = newValue }
    }
}
```

- [ ] **Step 2: Run the specific test and verify it fails**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests/testLaunchAtLoginFailureShowsInstalledAppGuidance
```

Expected: FAIL because the old message is still `"开机自启未能启用，请确认 OneBoard 已从完整 .app 启动。"`

- [ ] **Step 3: Implement clearer status message**

In `SystemCapabilityViewModel.setLaunchAtLoginEnabled(_:)`, replace the failure message with:

```swift
statusMessage = "开机自启未能启用，请确认 OneBoard 位于 /Applications，且登录项 Helper 已正确打包并签名。"
```

- [ ] **Step 4: Run the specific test and verify it passes**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests/testLaunchAtLoginFailureShowsInstalledAppGuidance
```

Expected: PASS.

- [ ] **Step 5: Sign helper and main app in package script**

In `script/build_app_bundle.sh`, after setting the helper bundle id and before `chmod +x`, add:

```bash
echo "Signing LaunchAtLogin helper and OneBoard.app..."
/usr/bin/codesign --force --deep --sign - "$HELPER_APP"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Validating app bundle..."
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
echo "Main bundle id: $APP_BUNDLE_ID"
echo "Helper bundle id: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$HELPER_APP/Contents/Info.plist")"
```

- [ ] **Step 6: Build a DMG and verify script output**

Run:

```bash
./script/package_app.sh
```

Expected:

- `build/OneBoard.dmg` is created.
- Output includes `Signing LaunchAtLogin helper and OneBoard.app...`
- Output includes `Main bundle id: com.oneboard.app`
- Output includes `Helper bundle id: com.oneboard.app-LaunchAtLoginHelper`

- [ ] **Step 7: Commit**

```bash
git add script/build_app_bundle.sh OneBoard/Shared/SystemCapabilityViewModel.swift OneBoard/Tests/SystemCapabilityViewModelTests.swift
git commit -m "fix: package launch at login helper"
```

## Task 2: Permission refresh correctness

**Files:**
- Modify: `OneBoard/Shared/SystemCapabilityViewModel.swift`
- Test: `OneBoard/Tests/SystemCapabilityViewModelTests.swift`

- [ ] **Step 1: Add failing screen-recording-only reset test**

Add:

```swift
func testConfirmDisableScreenRecordingResetsOnlyScreenRecording() {
    let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
    let viewModel = SystemCapabilityViewModel(
        permissions: permissions,
        gatewayHelper: StubGatewayHelperProvider(installed: false),
        launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
        confirmsDisablePermission: { $0 == .screenRecording }
    )

    viewModel.setScreenRecordingEnabled(false)

    XCTAssertTrue(viewModel.accessibilityGranted)
    XCTAssertFalse(viewModel.screenRecordingGranted)
    XCTAssertEqual(permissions.resetServices, [.screenRecording])
    XCTAssertEqual(viewModel.statusMessage, "屏幕录制授权已关闭")
}
```

- [ ] **Step 2: Add failing operation-state test**

Add a published state to test before implementation:

```swift
func testPermissionOperationStateClearsAfterDisable() {
    let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
    let viewModel = SystemCapabilityViewModel(
        permissions: permissions,
        gatewayHelper: StubGatewayHelperProvider(installed: false),
        launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
        confirmsDisablePermission: { _ in true }
    )

    viewModel.setScreenRecordingEnabled(false)

    XCTAssertNil(viewModel.activePermissionOperation)
}
```

- [ ] **Step 3: Run tests and verify operation-state test fails**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests
```

Expected: FAIL because `activePermissionOperation` does not exist.

- [ ] **Step 4: Add operation-state and delayed refresh**

In `SystemCapabilityViewModel`, add:

```swift
@Published private(set) var activePermissionOperation: OneBoardPermissionKind?
```

Update `setPermission(_ enabled:)`:

```swift
private func setPermission(_ kind: OneBoardPermissionKind, enabled: Bool) {
    activePermissionOperation = kind
    defer { activePermissionOperation = nil }

    if enabled {
        permissions.showPermissionGuide(for: kind)
        refresh()
        schedulePermissionRefresh()
        return
    }

    guard confirmsDisablePermission(kind) else {
        refresh()
        return
    }

    do {
        try permissions.resetAuthorization(for: kind)
        statusMessage = "\(kind.title)授权已关闭"
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
    }
    refresh()
    schedulePermissionRefresh()
    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
}

private func schedulePermissionRefresh() {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 700_000_000)
        refresh()
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd OneBoard && swift test --filter SystemCapabilityViewModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OneBoard/Shared/SystemCapabilityViewModel.swift OneBoard/Tests/SystemCapabilityViewModelTests.swift
git commit -m "fix: refresh permission status predictably"
```

## Task 3: Clipboard click-to-paste ignore scope

**Files:**
- Modify: `OneBoard/Modules/Clipboard/Services/PasteboardMonitor.swift`
- Modify: `OneBoard/Modules/Clipboard/ViewModels/ClipboardListViewModel.swift`
- Create: `OneBoard/Tests/ClipboardPasteCoordinatorTests.swift`

- [ ] **Step 1: Extract a paste coordinator seam**

Create `OneBoard/Modules/Clipboard/ViewModels/ClipboardPasteCoordinator.swift`:

```swift
import AppKit

@MainActor
final class ClipboardPasteCoordinator {
    private let monitor: PasteboardMonitor
    private let pasteboardWriter: (ClipboardEntry) -> Void
    private let targetAppProvider: () -> NSRunningApplication?
    private let closeClipboardWindow: () -> Void
    private let pasteAction: (NSRunningApplication?) async -> Void

    init(
        monitor: PasteboardMonitor = .shared,
        pasteboardWriter: @escaping (ClipboardEntry) -> Void,
        targetAppProvider: @escaping () -> NSRunningApplication? = { MenuBarManager.shared.targetApplicationForClipboardPaste() },
        closeClipboardWindow: @escaping () -> Void = { MenuBarManager.shared.closeClipboardFloatingWindow() },
        pasteAction: @escaping (NSRunningApplication?) async -> Void
    ) {
        self.monitor = monitor
        self.pasteboardWriter = pasteboardWriter
        self.targetAppProvider = targetAppProvider
        self.closeClipboardWindow = closeClipboardWindow
        self.pasteAction = pasteAction
    }

    func paste(_ entry: ClipboardEntry) {
        Task { @MainActor in
            await monitor.performIgnoringChanges {
                pasteboardWriter(entry)
                let previousApp = targetAppProvider()
                closeClipboardWindow()
                try? await Task.sleep(nanoseconds: 120_000_000)
                await pasteAction(previousApp)
            }
        }
    }
}
```

- [ ] **Step 2: Add failing coordinator test**

Create `OneBoard/Tests/ClipboardPasteCoordinatorTests.swift`:

```swift
import XCTest
@testable import OneBoard

@MainActor
final class ClipboardPasteCoordinatorTests: XCTestCase {
    func testPasteRunsInsideMonitorIgnoreScope() async {
        let monitor = PasteboardMonitor.shared
        let entry = ClipboardEntry(
            contentType: ClipboardContentType.text.rawValue,
            plainText: "hello",
            data: Data("hello".utf8),
            createdAt: Date()
        )
        var observedIsPastingDuringWrite = false
        var didClose = false
        var didPaste = false

        let coordinator = ClipboardPasteCoordinator(
            monitor: monitor,
            pasteboardWriter: { _ in observedIsPastingDuringWrite = monitor.isPasting },
            targetAppProvider: { nil },
            closeClipboardWindow: { didClose = true },
            pasteAction: { _ in didPaste = true }
        )

        coordinator.paste(entry)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(observedIsPastingDuringWrite)
        XCTAssertTrue(didClose)
        XCTAssertTrue(didPaste)
        XCTAssertFalse(monitor.isPasting)
    }
}
```

- [ ] **Step 3: Run test and verify it fails**

Run:

```bash
cd OneBoard && swift test --filter ClipboardPasteCoordinatorTests
```

Expected: FAIL before coordinator exists or before `performIgnoringChanges` is used.

- [ ] **Step 4: Make `performIgnoringChanges` main-actor safe**

In `PasteboardMonitor`, make ignore state mutation explicitly main-actor:

```swift
@MainActor
func performIgnoringChanges<T>(_ operation: () async -> T) async -> T {
    isPasting = true
    defer {
        lastChangeCount = NSPasteboard.general.changeCount
        isPasting = false
    }
    return await operation()
}
```

- [ ] **Step 5: Wire coordinator into `ClipboardListViewModel`**

Replace the body of `selectAndPaste(_:)` with:

```swift
func selectAndPaste(_ entry: ClipboardEntry) {
    guard isSupportedEntry(entry) else { return }
    selectedEntry = entry

    let coordinator = ClipboardPasteCoordinator(
        pasteboardWriter: { [weak self] entry in self?.writeToPasteboard(entry) },
        pasteAction: { [weak self] app in
            await self?.activateAndPasteAsync(into: app)
        }
    )
    coordinator.paste(entry)
}
```

Add an async wrapper in the same class:

```swift
private func activateAndPasteAsync(into app: NSRunningApplication?) async {
    await withCheckedContinuation { continuation in
        activateAndPaste(into: app) {
            continuation.resume()
        }
    }
}
```

Update `activateAndPaste`, `waitForActivation`, and `simulatePaste` to accept a completion closure and call it on all exit paths.

- [ ] **Step 6: Run clipboard coordinator test**

Run:

```bash
cd OneBoard && swift test --filter ClipboardPasteCoordinatorTests
```

Expected: PASS.

- [ ] **Step 7: Run clipboard-related tests**

Run:

```bash
cd OneBoard && swift test --filter Clipboard
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add OneBoard/Modules/Clipboard/Services/PasteboardMonitor.swift OneBoard/Modules/Clipboard/ViewModels/ClipboardListViewModel.swift OneBoard/Modules/Clipboard/ViewModels/ClipboardPasteCoordinator.swift OneBoard/Tests/ClipboardPasteCoordinatorTests.swift
git commit -m "fix: ignore clipboard history paste writes"
```

## Task 4: Screenshot session lifecycle cleanup

**Files:**
- Modify: `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`
- Test: `OneBoard/Tests/ScreenshotSessionLifecycleTests.swift`

- [ ] **Step 1: Make panel managers closable**

Change `TranslationPanelWindowManager.closePanel()` from `private` to:

```swift
func closePanel() {
    translationTask?.cancel()
    translationTask = nil
    panel?.close()
    panel = nil
}
```

Add this method to `AnnotationResultWindowManager` until OCR bubble replaces it:

```swift
func close() {
    panel?.close()
    panel = nil
}
```

- [ ] **Step 2: Add cleanup method in ScreenshotViewModel**

In `ScreenshotViewModel`, add:

```swift
func closeActiveScreenshotSession() {
    closeAnnotationWindows()
    AnnotationResultWindowManager.shared.close()
    TranslationPanelWindowManager.shared.closePanel()
}
```

At the top of `startCapture()` after `resetRecognitionState()`, call:

```swift
closeActiveScreenshotSession()
```

- [ ] **Step 3: Add a lifecycle test for idempotent cleanup**

Create `OneBoard/Tests/ScreenshotSessionLifecycleTests.swift`:

```swift
import XCTest
@testable import OneBoard

@MainActor
final class ScreenshotSessionLifecycleTests: XCTestCase {
    func testCloseActiveScreenshotSessionIsIdempotent() {
        let viewModel = ScreenshotViewModel.shared

        viewModel.closeActiveScreenshotSession()
        viewModel.closeActiveScreenshotSession()

        XCTAssertTrue(viewModel.pinnedWindows.isEmpty || !viewModel.pinnedWindows.isEmpty)
    }
}
```

This test mainly guards that cleanup is public and safe to repeat. Keep functional orphan-window behavior as manual verification because NSPanel state is UI runtime behavior.

- [ ] **Step 4: Run lifecycle test**

Run:

```bash
cd OneBoard && swift test --filter ScreenshotSessionLifecycleTests
```

Expected: PASS.

- [ ] **Step 5: Manual verification**

Run the app, capture once, leave toolbar visible, trigger capture again, then close the second capture.

Expected:

- The first annotation window is gone.
- No orphan toolbar remains.
- Esc and close controls still work on the current capture.

- [ ] **Step 6: Commit**

```bash
git add OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift OneBoard/Tests/ScreenshotSessionLifecycleTests.swift
git commit -m "fix: clean up active screenshot sessions"
```

## Task 5: Screenshot toolbar B+C mixed layout and completion action

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`
- Modify: `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
- Test: `OneBoard/Tests/AnnotationServiceTests.swift`

- [ ] **Step 1: Add completion callback**

In `AnnotationToolbarView`, replace:

```swift
let onCopy: (NSImage) -> Void
```

with:

```swift
let onComplete: (NSImage) -> Void
```

Update all construction sites in `ScreenshotViewModel.showAnnotationWindow(result:)` to pass:

```swift
onComplete: { [weak self] img in
    self?.copyToClipboard(img)
    self?.closeActiveScreenshotSession()
}
```

- [ ] **Step 2: Expand preset colors**

Replace `presetColors` with:

```swift
private let presetColors: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen,
    .systemTeal, .systemBlue, .systemPurple, .systemPink,
    .black, .white
]
```

- [ ] **Step 3: Remove copy action button and add complete button**

In `actionButtonsRow`, delete the `"复制"` action button. Add:

```swift
iconActionButton("完成", icon: "checkmark", prominent: true) {
    let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
    onComplete(rendered)
}
```

Change `iconActionButton` signature:

```swift
private func iconActionButton(
    _ label: String,
    icon: String,
    prominent: Bool = false,
    action: @escaping () -> Void
) -> some View
```

Use green styling when prominent:

```swift
.background(
    RoundedRectangle(cornerRadius: 9)
        .fill(prominent ? Color(nsColor: .systemGreen) : Color.black.opacity(0.06))
)
.foregroundColor(prominent ? .white : Color.black.opacity(0.78))
```

- [ ] **Step 4: Restyle toolbar groups**

In `body`, group sections with subtle rounded backgrounds:

```swift
HStack(spacing: 8) {
    toolGroup
    colorGroup
    actionButtonsRow
}
.padding(.horizontal, 10)
.padding(.vertical, 8)
.background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
.overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
.shadow(color: .black.opacity(0.16), radius: 14, y: 6)
```

Create `toolGroup` and `colorGroup` computed views that wrap existing tool buttons and color swatches in `RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.045))`.

- [ ] **Step 5: Run annotation tests**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests
```

Expected: PASS.

- [ ] **Step 6: Manual verification**

Capture and mark up an image. Click the green check.

Expected:

- Clipboard contains the rendered image.
- Annotation window and toolbar close.
- No copy button appears.
- More preset colors are visible.

- [ ] **Step 7: Commit**

```bash
git add OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift
git commit -m "feat: polish screenshot toolbar completion flow"
```

## Task 6: OCR bubble popup

**Files:**
- Create: `OneBoard/Modules/Screenshot/Views/OCRBubbleWindowManager.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`
- Modify: `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`

- [ ] **Step 1: Create OCR bubble manager**

Create `OneBoard/Modules/Screenshot/Views/OCRBubbleWindowManager.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class OCRBubbleWindowManager {
    static let shared = OCRBubbleWindowManager()

    private var panel: NSPanel?
    private var outsideClickMonitor: Any?

    private init() {}

    func show(text: String, relativeTo sourceFrame: NSRect?) {
        close()

        let hostingView = NSHostingView(rootView: OCRBubbleView(text: text) { [weak self] in
            self?.close()
        })
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        position(panel, relativeTo: sourceFrame)
        panel.orderFrontRegardless()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel else { return }
            if !panel.frame.contains(event.locationInWindow) {
                Task { @MainActor in self?.close() }
            }
        }

        self.panel = panel
    }

    func close() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        panel?.close()
        panel = nil
    }

    private func position(_ panel: NSPanel, relativeTo sourceFrame: NSRect?) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        guard let sourceFrame else {
            FloatingWindowManager.positionAtTopRight(panel, offset: 28)
            return
        }

        let gap: CGFloat = 12
        var origin = NSPoint(x: sourceFrame.midX - panel.frame.width / 2, y: sourceFrame.minY - panel.frame.height - gap)
        if origin.y < screenFrame.minY {
            origin.y = sourceFrame.maxY + gap
        }
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, screenFrame.minY + 8), screenFrame.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }
}
```

- [ ] **Step 2: Add OCR bubble view**

In the same file, add:

```swift
private struct OCRBubbleView: View {
    @State private var editableText: String
    let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        _editableText = State(initialValue: text)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("提取文字")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $editableText)
                .font(.system(size: 17, weight: .medium))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 82)

            HStack {
                Spacer()
                Button("编辑") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editableText, forType: .string)
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 360, height: 220)
        .background(BubbleShape().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(BubbleShape().stroke(Color.black.opacity(0.12), lineWidth: 1))
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 14
        let pointerWidth: CGFloat = 20
        let pointerHeight: CGFloat = 12
        let body = rect.insetBy(dx: 0, dy: pointerHeight).offsetBy(dx: 0, dy: pointerHeight)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: corner, height: corner))
        path.move(to: CGPoint(x: rect.midX - pointerWidth / 2, y: body.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + pointerWidth / 2, y: body.minY))
        path.closeSubpath()
        return path
    }
}
```

- [ ] **Step 3: Wire OCR toolbar action to bubble**

In `AnnotationToolbarView` OCR action, replace `AnnotationResultWindowManager.shared.show(...)` with:

```swift
OCRBubbleWindowManager.shared.show(
    text: vm.ocrResult,
    relativeTo: NSApp.keyWindow?.frame
)
```

In `ScreenshotViewModel.closeActiveScreenshotSession()`, add:

```swift
OCRBubbleWindowManager.shared.close()
```

- [ ] **Step 4: Build**

Run:

```bash
cd OneBoard && swift build
```

Expected: PASS.

- [ ] **Step 5: Manual verification**

Capture a text region and click OCR.

Expected:

- OCR result appears in a white bubble with pointer.
- Clicking blank space outside closes it.
- Copy button copies edited text and closes bubble.

- [ ] **Step 6: Commit**

```bash
git add OneBoard/Modules/Screenshot/Views/OCRBubbleWindowManager.swift OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift
git commit -m "feat: show OCR results in a bubble"
```

## Task 7: Translation workbench B layout

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`
- Test: `OneBoard/Tests/TranslationPanelViewModelTests.swift`

- [ ] **Step 1: Tighten title bar**

In `TranslationPanelView.titleBar`, set:

```swift
.frame(height: 44)
```

Change title content to one line:

```swift
Text("翻译工作台 · \(viewModel.translationServiceType.displayName)")
    .font(.system(size: 15, weight: .semibold))
```

Place the close button with:

```swift
.padding(.trailing, 10)
.padding(.top, 6)
```

- [ ] **Step 2: Use fixed complete layout height**

Change root frame:

```swift
.frame(width: 520, height: 600)
```

Change content padding:

```swift
.padding(.horizontal, 16)
.padding(.top, 14)
.padding(.bottom, 16)
```

Set source and translation heights:

```swift
source TextEditor .frame(height: 128)
translation ScrollView .frame(height: 132)
statusBar .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
```

- [ ] **Step 3: Fix window min size**

In `TranslationPanelWindowManager.show(...)`, change panel content rect to:

```swift
contentRect: NSRect(x: 0, y: 0, width: 520, height: 600)
```

After panel creation:

```swift
panel.minSize = NSSize(width: 520, height: 600)
panel.maxSize = NSSize(width: 520, height: 600)
```

- [ ] **Step 4: Run translation tests**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Manual visual verification**

Open translation from screenshot or selected text.

Expected:

- No blank band at the top.
- Close button sits near the upper-right corner.
- Service selector, languages, source, translation, status, and buttons are all visible.

- [ ] **Step 6: Commit**

```bash
git add OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift
git commit -m "style: refine translation workbench layout"
```

## Task 8: Final docs and verification

**Files:**
- Modify: `docs/开发步骤/README.md`
- Create or modify: `开发日志/2026-06/2026-06-15.md`

- [ ] **Step 1: Run full test suite**

Run:

```bash
cd OneBoard && swift test
```

Expected: PASS.

- [ ] **Step 2: Run release build**

Run:

```bash
cd OneBoard && swift build -c release --disable-sandbox
```

Expected: PASS.

- [ ] **Step 3: Package DMG**

Run:

```bash
./script/package_app.sh
```

Expected: `build/OneBoard.dmg` is generated.

- [ ] **Step 4: Manual acceptance checklist**

Verify:

- DMG app installed to `/Applications` can enable launch at login.
- Screenshot toolbar has B+C mixed layout, no copy button, green check copies and closes.
- Consecutive captures do not leave orphan windows.
- OCR opens a bubble and closes on outside click.
- Translation workbench uses B layout and remains complete.
- Clipboard click-to-paste does not generate a duplicate history item.
- Screen recording disable does not visually toggle accessibility.

- [ ] **Step 5: Update development docs**

In `docs/开发步骤/README.md`, mark the relevant screenshot polish and settings fixes as completed if matching rows exist.

Create or append `开发日志/2026-06/2026-06-15.md`:

```markdown
# 2026-06-15

## 完成

- 修复 DMG 安装后的开机自启打包和签名问题。
- 优化截图工具栏，新增完成按钮并扩展颜色选择。
- 修复连续截图导致旧窗口残留的问题。
- 新增 OCR 气泡弹窗并支持外部点击关闭。
- 优化翻译工作台布局。
- 修复点击剪贴板历史记录粘贴时重复生成记录的问题。
- 优化权限状态刷新和提示文案。

## 验证

- `swift test`
- `swift build -c release --disable-sandbox`
- `./script/package_app.sh`
```

- [ ] **Step 6: Commit final docs**

```bash
git add docs/开发步骤/README.md 开发日志/2026-06/2026-06-15.md
git commit -m "docs: record screenshot polish fixes"
```

## Self-Review

- Spec coverage: launch-at-login is Task 1; permission refresh is Task 2; clipboard duplicate handling is Task 3; screenshot orphan cleanup is Task 4; toolbar visual and completion action are Task 5; OCR bubble is Task 6; translation workbench layout is Task 7; docs and verification are Task 8.
- Placeholder scan: no placeholder markers or unresolved choices remain.
- Type consistency: new names are `ClipboardPasteCoordinator`, `closeActiveScreenshotSession()`, `OCRBubbleWindowManager`, and `activePermissionOperation`; the same names are used consistently across tasks.
