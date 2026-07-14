# Screenshot Selection Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复截图结果上下镜像，并实现“松开后原位调整选区，点击工具后锁定并进入标注”的两阶段截图交互。

**Architecture:** 将屏幕坐标映射、选区几何与交互状态抽成可测试的纯 Swift 类型；`ScreenshotOverlayContentView` 只负责把鼠标事件和工具栏动作转交给模型。锁定动作携带用户选择的标注或输出命令，通过现有 `ScreenshotCaptureService` 交给 `ScreenshotViewModel`，标注阶段继续复用当前标注窗口与工具栏。

**Tech Stack:** Swift 5.9+、AppKit、SwiftUI、XCTest、Swift Package Manager，目标 macOS 14.0+。

## Global Constraints

- 可执行模块 `OneBoard` 保持极简，业务代码只放在 `OneBoardKit`。
- 裁剪图像时需要翻转 Y；AppKit 屏幕窗口定位不得翻转 Y。
- 标注锁定前允许移动与八方向缩放；锁定后不允许改变选区。
- 选区限制在开始截图的屏幕内，不实现跨屏拖动。
- Retina 像素换算只用于裁剪；窗口布局使用逻辑点。
- 修改后从 `OneBoard/` 运行测试，并重新打包、校验 DMG。

---

## File Structure

- Create `OneBoard/Modules/Screenshot/Models/ScreenshotSelection.swift`: 选区阶段、拖动意图、八方向控制点、纯几何模型和锁定动作。
- Create `OneBoard/Modules/Screenshot/Views/ScreenshotSelectionToolbarView.swift`: 调整阶段显示的工具与输出按钮，仅发送动作，不持有截图数据。
- Modify `OneBoard/Modules/Screenshot/Models/AnnotationLayer.swift`: 为 `ScreenshotResult` 增加锁定动作。
- Modify `OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift`: 修正屏幕坐标；接入选区模型、控制点、工具栏与一次性锁定。
- Modify `OneBoard/Modules/Screenshot/Services/ScreenshotCaptureService.swift`: 将锁定动作写入 `ScreenshotResult`。
- Modify `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`: 根据锁定动作进入指定标注工具或执行输出操作。
- Modify `OneBoard/Tests/ScreenshotOverlayCropTests.swift`: 覆盖顶部选区的 AppKit 屏幕坐标与 Retina 裁剪坐标。
- Create `OneBoard/Tests/ScreenshotSelectionTests.swift`: 覆盖移动、八方向缩放、重新框选、最小尺寸、边界约束和锁定不可变。

---

### Task 1: Separate Crop and Screen Coordinate Mapping

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift:23-52`
- Test: `OneBoard/Tests/ScreenshotOverlayCropTests.swift`

**Interfaces:**
- Consumes: Overlay 局部坐标 `CGRect`、当前屏幕全局 `screenFrame`。
- Produces: `ScreenshotCropMapper.cropRect(...) -> CGRect` 和 `ScreenshotCropMapper.screenRect(...) -> CGRect`。

- [ ] **Step 1: Write the failing top-selection screen-coordinate test**

```swift
func testScreenRectKeepsTopSelectionAtTopOfScreen() {
    let screenFrame = CGRect(x: -1440, y: 120, width: 1440, height: 900)
    let overlayRect = CGRect(x: 100, y: 700, width: 400, height: 120)

    let result = ScreenshotCropMapper.screenRect(
        forOverlayRect: overlayRect,
        screenFrame: screenFrame
    )

    XCTAssertEqual(result, CGRect(x: -1340, y: 820, width: 400, height: 120))
}

func testCropRectStillFlipsYForCGImagePixels() {
    let result = ScreenshotCropMapper.cropRect(
        forOverlayRect: CGRect(x: 100, y: 700, width: 400, height: 120),
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        imagePixelSize: CGSize(width: 2880, height: 1800)
    )

    XCTAssertEqual(result, CGRect(x: 200, y: 160, width: 800, height: 240))
}
```

- [ ] **Step 2: Run the focused test and verify the screen-coordinate case fails**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotOverlayCropTests`

Expected: `testScreenRectKeepsTopSelectionAtTopOfScreen` fails because the current implementation returns a vertically mirrored Y value; the crop test passes.

- [ ] **Step 3: Remove Y flipping only from AppKit screen placement**

```swift
static func screenRect(forOverlayRect rect: CGRect, screenFrame: CGRect) -> CGRect {
    CGRect(
        x: screenFrame.minX + rect.minX,
        y: screenFrame.minY + rect.minY,
        width: rect.width,
        height: rect.height
    )
}
```

- [ ] **Step 4: Run the focused tests and verify both coordinate systems pass**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotOverlayCropTests`

Expected: all `ScreenshotOverlayCropTests` pass with zero failures.

- [ ] **Step 5: Commit the coordinate fix**

```bash
git add OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift OneBoard/Tests/ScreenshotOverlayCropTests.swift
git commit -m "fix: preserve screenshot selection screen position"
```

---

### Task 2: Add a Pure Selection Geometry and State Model

**Files:**
- Create: `OneBoard/Modules/Screenshot/Models/ScreenshotSelection.swift`
- Create: `OneBoard/Tests/ScreenshotSelectionTests.swift`

**Interfaces:**
- Produces: `ScreenshotResizeHandle`, `ScreenshotSelectionPhase`, `ScreenshotSelectionModel`, `ScreenshotSelectionAction`.
- `ScreenshotSelectionModel.begin(at:bounds:)`, `update(to:bounds:)`, `end(at:bounds:)`, and `lock() -> CGRect?` are consumed by the overlay in Task 4.

- [ ] **Step 1: Write failing tests for creation, movement, resize, restart, and locking**

Create `OneBoard/Tests/ScreenshotSelectionTests.swift` with deterministic geometry cases:

```swift
import CoreGraphics
@testable import OneBoardKit
import XCTest

final class ScreenshotSelectionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)

    func testMovingSelectionClampsToScreenBounds() {
        let result = ScreenshotSelectionGeometry.moved(
            CGRect(x: 800, y: 500, width: 180, height: 160),
            by: CGSize(width: 100, height: 100),
            inside: bounds
        )
        XCTAssertEqual(result, CGRect(x: 820, y: 540, width: 180, height: 160))
    }

    func testTopLeftResizeMovesOnlyTopAndLeftEdges() {
        let result = ScreenshotSelectionGeometry.resized(
            CGRect(x: 200, y: 200, width: 300, height: 200),
            handle: .topLeft,
            to: CGPoint(x: 150, y: 460),
            inside: bounds,
            minimumSize: CGSize(width: 24, height: 24)
        )
        XCTAssertEqual(result, CGRect(x: 150, y: 200, width: 350, height: 260))
    }

    func testEveryResizeHandleProducesAValidRect() {
        let original = CGRect(x: 200, y: 200, width: 300, height: 200)
        for handle in ScreenshotResizeHandle.allCases {
            let result = ScreenshotSelectionGeometry.resized(
                original,
                handle: handle,
                to: handle.testPoint(for: original, offset: 40),
                inside: bounds,
                minimumSize: CGSize(width: 24, height: 24)
            )
            XCTAssertGreaterThanOrEqual(result.width, 24)
            XCTAssertGreaterThanOrEqual(result.height, 24)
            XCTAssertTrue(bounds.contains(result))
        }
    }

    func testClickOutsideExistingSelectionStartsNewSelection() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.begin(at: CGPoint(x: 700, y: 500), bounds: bounds)
        model.update(to: CGPoint(x: 850, y: 620), bounds: bounds)
        model.end(at: CGPoint(x: 850, y: 620), bounds: bounds)
        XCTAssertEqual(model.rect, CGRect(x: 700, y: 500, width: 150, height: 120))
        XCTAssertEqual(model.phase, .adjusting)
    }

    func testLockPreventsFurtherGeometryChanges() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(model.lock(), model.rect)
        model.begin(at: CGPoint(x: 150, y: 150), bounds: bounds)
        model.update(to: CGPoint(x: 400, y: 400), bounds: bounds)
        model.end(at: CGPoint(x: 400, y: 400), bounds: bounds)
        XCTAssertEqual(model.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(model.phase, .locked)
    }
}
```

The production file also supplies an internal `testPoint(for:offset:)` helper under `#if DEBUG` only if the test requires it; otherwise put the point mapping in the test target.

- [ ] **Step 2: Run tests and verify the new symbols are missing**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotSelectionTests`

Expected: compilation fails because `ScreenshotSelectionGeometry`, `ScreenshotSelectionModel`, and related enums do not exist.

- [ ] **Step 3: Implement the focused model**

Create `OneBoard/Modules/Screenshot/Models/ScreenshotSelection.swift` with these public-to-module declarations and complete behavior:

```swift
import CoreGraphics

enum ScreenshotResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

enum ScreenshotSelectionPhase: Equatable {
    case selecting
    case adjusting
    case locked
}

enum ScreenshotSelectionAction: Equatable {
    case annotate(AnnotationTool)
    case copy
    case save
    case pin
    case ocr
    case translate
}

enum ScreenshotSelectionGeometry {
    static func moved(_ rect: CGRect, by translation: CGSize, inside bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX + translation.width, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + translation.height, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }

    static func resized(
        _ rect: CGRect,
        handle: ScreenshotResizeHandle,
        to point: CGPoint,
        inside bounds: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if [.topLeft, .left, .bottomLeft].contains(handle) {
            minX = min(max(point.x, bounds.minX), maxX - minimumSize.width)
        }
        if [.topRight, .right, .bottomRight].contains(handle) {
            maxX = max(min(point.x, bounds.maxX), minX + minimumSize.width)
        }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) {
            minY = min(max(point.y, bounds.minY), maxY - minimumSize.height)
        }
        if [.topLeft, .top, .topRight].contains(handle) {
            maxY = max(min(point.y, bounds.maxY), minY + minimumSize.height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

Add `ScreenshotSelectionModel` with an internal drag enum carrying the anchor/original rect. `begin` must choose resize first, then move, then new selection; `update` delegates to the geometry functions; `end` enters `.adjusting` only for a rect at least `24×24`; `lock` returns the rect once and changes the phase to `.locked`; all later mutations are ignored.

- [ ] **Step 4: Run the selection tests**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotSelectionTests`

Expected: all geometry and phase tests pass with zero failures.

- [ ] **Step 5: Commit the selection model**

```bash
git add OneBoard/Modules/Screenshot/Models/ScreenshotSelection.swift OneBoard/Tests/ScreenshotSelectionTests.swift
git commit -m "feat: add adjustable screenshot selection model"
```

---

### Task 3: Add the Pre-Lock Selection Toolbar and Action Contract

**Files:**
- Create: `OneBoard/Modules/Screenshot/Views/ScreenshotSelectionToolbarView.swift`
- Modify: `OneBoard/Modules/Screenshot/Models/AnnotationLayer.swift:80-84`
- Test: `OneBoard/Tests/ScreenshotSelectionTests.swift`

**Interfaces:**
- Consumes: `ScreenshotSelectionAction`, `AnnotationTool.allCases` and the existing icon metadata.
- Produces: `ScreenshotSelectionToolbarView(onAction:)` and `ScreenshotResult.action`.

- [ ] **Step 1: Add failing action-contract and toolbar-layout tests**

```swift
func testToolbarUsesTopWhenBottomWouldLeaveBounds() {
    let frame = ScreenshotSelectionToolbarLayout.frame(
        selectionRect: CGRect(x: 200, y: 10, width: 400, height: 220),
        toolbarSize: CGSize(width: 520, height: 44),
        bounds: bounds,
        gap: 12
    )
    XCTAssertEqual(frame.minY, 242)
    XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
    XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX)
}

func testScreenshotResultKeepsLockAction() {
    let image = NSImage(size: CGSize(width: 100, height: 80))
    let result = ScreenshotResult(
        image: image,
        selectionRect: CGRect(x: 20, y: 30, width: 100, height: 80),
        action: .annotate(.arrow)
    )
    XCTAssertEqual(result.action, .annotate(.arrow))
}
```

- [ ] **Step 2: Run tests and verify the new layout/action contract is absent**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotSelectionTests`

Expected: compilation fails for `ScreenshotSelectionToolbarLayout` and the missing `ScreenshotResult.action` initializer argument.

- [ ] **Step 3: Implement toolbar layout and result action**

Add to `ScreenshotSelection.swift`:

```swift
enum ScreenshotSelectionToolbarLayout {
    static func frame(
        selectionRect: CGRect,
        toolbarSize: CGSize,
        bounds: CGRect,
        gap: CGFloat
    ) -> CGRect {
        let belowY = selectionRect.minY - gap - toolbarSize.height
        let y = belowY >= bounds.minY
            ? belowY
            : min(selectionRect.maxY + gap, bounds.maxY - toolbarSize.height)
        let centeredX = selectionRect.midX - toolbarSize.width / 2
        let x = min(max(centeredX, bounds.minX), bounds.maxX - toolbarSize.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }
}
```

Change the result model to:

```swift
struct ScreenshotResult {
    let image: NSImage
    let selectionRect: CGRect
    let action: ScreenshotSelectionAction
}
```

- [ ] **Step 4: Create the adjustment-stage toolbar**

Create `ScreenshotSelectionToolbarView.swift`. It must render annotation buttons for `.rectangle`, `.ellipse`, `.arrow`, `.line`, `.text`, `.number`, and `.mosaic`, plus copy, save, pin, OCR, and translate buttons. Every button calls exactly one closure:

```swift
struct ScreenshotSelectionToolbarView: View {
    let onAction: (ScreenshotSelectionAction) -> Void

    private let annotationTools: [AnnotationTool] = [
        .rectangle, .ellipse, .arrow, .line, .text, .number, .mosaic,
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(annotationTools, id: \.self) { tool in
                button(icon: tool.iconName, help: tool.displayName) {
                    onAction(.annotate(tool))
                }
            }
            Divider().frame(height: 22)
            button(icon: "doc.on.doc", help: "复制") { onAction(.copy) }
            button(icon: "square.and.arrow.down", help: "保存") { onAction(.save) }
            button(icon: "pin", help: "贴图") { onAction(.pin) }
            button(icon: "text.viewfinder", help: "OCR") { onAction(.ocr) }
            button(icon: "character.bubble", help: "翻译") { onAction(.translate) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OneBoardRadius.lg))
    }
}
```

Implement the private `button(icon:help:action:)` using the same 28×28 plain-button styling as `AnnotationToolbarView`, without duplicating color/style/history controls that have no meaning before a cropped image exists.

- [ ] **Step 5: Run the focused tests**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotSelectionTests`

Expected: toolbar layout and action-contract tests pass.

- [ ] **Step 6: Commit the toolbar contract**

```bash
git add OneBoard/Modules/Screenshot/Models/ScreenshotSelection.swift OneBoard/Modules/Screenshot/Models/AnnotationLayer.swift OneBoard/Modules/Screenshot/Views/ScreenshotSelectionToolbarView.swift OneBoard/Tests/ScreenshotSelectionTests.swift
git commit -m "feat: add screenshot selection action toolbar"
```

---

### Task 4: Integrate Adjustable Selection Into the Overlay

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift:54-270`
- Modify: `OneBoard/Modules/Screenshot/Services/ScreenshotCaptureService.swift:20-50`
- Test: `OneBoard/Tests/ScreenshotSelectionTests.swift`

**Interfaces:**
- Consumes: `ScreenshotSelectionModel`, `ScreenshotSelectionToolbarLayout`, `ScreenshotSelectionAction`.
- Produces: overlay callback `(NSImage, CGRect, ScreenshotSelectionAction) -> Void` and a `ScreenshotResult` containing the action.

- [ ] **Step 1: Add a red test for one-time locking**

```swift
func testLockReturnsSelectionOnlyOnce() {
    var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))
    XCTAssertEqual(model.lock(), CGRect(x: 100, y: 100, width: 200, height: 150))
    XCTAssertNil(model.lock())
}
```

- [ ] **Step 2: Run the test and verify a second lock is currently possible**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotSelectionTests/testLockReturnsSelectionOnlyOnce`

Expected: FAIL until `lock()` guards `phase != .locked` and returns `nil` after the first transition.

- [ ] **Step 3: Replace immediate mouse-up confirmation with model-driven adjustment**

In `ScreenshotOverlayContentView`:

```swift
private var selectionModel = ScreenshotSelectionModel()
private var hasFinished = false
private var toolbarHostingView: NSHostingView<ScreenshotSelectionToolbarView>?

private var selectionRect: CGRect? { selectionModel.rect }

override func mouseDown(with event: NSEvent) {
    guard !hasFinished else { return }
    hideSelectionToolbar()
    selectionModel.begin(at: convert(event.locationInWindow, from: nil), bounds: bounds)
    needsDisplay = true
}

override func mouseDragged(with event: NSEvent) {
    guard !hasFinished else { return }
    selectionModel.update(to: convert(event.locationInWindow, from: nil), bounds: bounds)
    needsDisplay = true
}

override func mouseUp(with event: NSEvent) {
    guard !hasFinished else { return }
    selectionModel.end(at: convert(event.locationInWindow, from: nil), bounds: bounds)
    showSelectionToolbarIfNeeded()
    needsDisplay = true
}
```

The draw path keeps the clear selection hole and border, adds eight visible handle circles from the model's handle centers, and only shows the initial hint when there is no valid rect.

- [ ] **Step 4: Host and reposition the adjustment toolbar**

`showSelectionToolbarIfNeeded()` creates one `NSHostingView(rootView: ScreenshotSelectionToolbarView { [weak self] action in self?.lockSelection(action) })`, adds it as a subview, measures `fittingSize`, and applies `ScreenshotSelectionToolbarLayout.frame(...)`. During move/resize the toolbar is hidden; on mouse-up it is remeasured and placed relative to the new rect. `removeFromSuperview()` removes the toolbar and calls `eventManager.cleanup()`.

- [ ] **Step 5: Lock, crop, and forward exactly once**

Replace `confirmCurrentSelection()` with:

```swift
private func lockSelection(_ action: ScreenshotSelectionAction = .annotate(.cursor)) {
    guard !hasFinished,
          let rect = selectionModel.lock(),
          rect.width > 10,
          rect.height > 10,
          let screen = window?.screen ?? NSScreen.main,
          let cg = cachedCGImage else { return }

    let crop = ScreenshotCropMapper.cropRect(
        forOverlayRect: rect,
        screenFrame: screen.frame,
        imagePixelSize: imagePixelSize
    )
    guard crop.width > 10, crop.height > 10, let cropped = cg.cropping(to: crop) else {
        selectionModel.unlockAfterFailedCrop()
        showSelectionToolbarIfNeeded()
        return
    }

    hasFinished = true
    let result = NSImage(cgImage: cropped, size: rect.size)
    onConfirm?(
        result,
        ScreenshotCropMapper.screenRect(forOverlayRect: rect, screenFrame: screen.frame),
        action
    )
}
```

Define `unlockAfterFailedCrop()` narrowly: it changes `.locked` back to `.adjusting` without changing the rect. Enter invokes `.annotate(.cursor)`; Esc cancels. A double-click inside a valid selection may invoke the same default action.

- [ ] **Step 6: Carry the action through capture service**

Change all overlay wrapper callback types to `(NSImage, CGRect, ScreenshotSelectionAction) -> Void`, then update capture service:

```swift
overlayView.onConfirm = { [weak eventManager] image, rect, action in
    eventManager?.cleanup()
    finish(ScreenshotResult(image: image, selectionRect: rect, action: action))
}
```

- [ ] **Step 7: Run screenshot selection and crop tests**

Run: `cd OneBoard && swift test --disable-sandbox --filter 'Screenshot(Selection|OverlayCrop)Tests'`

Expected: all selection state, geometry, toolbar layout and coordinate tests pass.

- [ ] **Step 8: Commit overlay integration**

```bash
git add OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift OneBoard/Modules/Screenshot/Services/ScreenshotCaptureService.swift OneBoard/Tests/ScreenshotSelectionTests.swift
git commit -m "feat: keep screenshot selection adjustable until tool choice"
```

---

### Task 5: Enter the Chosen Tool and Complete Verification

**Files:**
- Modify: `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift:58-219`
- Modify: `OneBoard/Tests/ScreenshotSessionLifecycleTests.swift`

**Interfaces:**
- Consumes: `ScreenshotResult.action` from Task 3/4.
- Produces: initial annotation tool selection or an immediate output operation using the locked image and selection rect.

- [ ] **Step 1: Add failing routing tests for selection actions**

Extract a pure routing decision:

```swift
enum ScreenshotLockedRoute: Equatable {
    case annotation(AnnotationTool)
    case copy, save, pin, ocr, translate
}

extension ScreenshotLockedRoute {
    static func route(for action: ScreenshotSelectionAction) -> Self {
        switch action {
        case .annotate(let tool): return .annotation(tool)
        case .copy: return .copy
        case .save: return .save
        case .pin: return .pin
        case .ocr: return .ocr
        case .translate: return .translate
        }
    }
}
```

Test it in `ScreenshotSessionLifecycleTests.swift`:

```swift
func testAnnotationSelectionRoutesToChosenTool() {
    XCTAssertEqual(
        ScreenshotLockedRoute.route(for: .annotate(.mosaic)),
        .annotation(.mosaic)
    )
}

func testOutputSelectionKeepsImmediateOperation() {
    XCTAssertEqual(ScreenshotLockedRoute.route(for: .ocr), .ocr)
}
```

- [ ] **Step 2: Run tests and verify the route type does not exist**

Run: `cd OneBoard && swift test --disable-sandbox --filter ScreenshotSessionLifecycleTests`

Expected: compilation fails for `ScreenshotLockedRoute`.

- [ ] **Step 3: Route the locked result**

After `captureRegion()` returns, set `capturedImage` and switch on the route:

```swift
capturedImage = result.image
switch ScreenshotLockedRoute.route(for: result.action) {
case .annotation(let tool):
    showAnnotationWindow(result: result, initialTool: tool)
case .copy:
    copyToClipboard(result.image)
case .save:
    saveRenderedImageToDesktop(result.image)
case .pin:
    pinToScreen(result.image, preferredFrame: result.selectionRect)
case .ocr:
    await performOCR(on: result.image)
    OCRBubbleWindowManager.shared.show(text: ocrResult, relativeTo: result.selectionRect)
case .translate:
    await performTranslation(on: result.image)
}
```

Change the annotation entry point to select the requested tool before creating views:

```swift
private func showAnnotationWindow(result: ScreenshotResult, initialTool: AnnotationTool) {
    let annotationService = AnnotationService(baseImage: result.image)
    annotationService.selectedColor = .systemRed
    annotationService.selectedTool = initialTool
    // Keep the existing window, canvas, toolbar, observer, and output wiring.
}
```

The annotation window remains non-resizable and uses the corrected `selectionRect` origin, so after lock the user cannot alter screenshot bounds.

- [ ] **Step 4: Run focused and complete tests**

Run: `cd OneBoard && swift test --disable-sandbox --filter 'Screenshot(Selection|OverlayCrop|SessionLifecycle)Tests'`

Expected: all screenshot tests pass.

Run: `cd OneBoard && swift test --disable-sandbox`

Expected: complete test suite passes with zero failures.

- [ ] **Step 5: Run release build and inspect the diff**

Run: `cd OneBoard && swift build -c release --disable-sandbox`

Expected: `Build complete!`; existing unrelated warnings may remain, but no new errors.

Run: `git diff --check && git diff --stat && rg -n '\[DEBUG-' OneBoard/Modules/Screenshot OneBoard/Tests || true`

Expected: no whitespace errors, no temporary debug instrumentation, and only planned screenshot files plus the pre-existing file-staging changes are present.

- [ ] **Step 6: Commit the routing integration**

```bash
git add OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift OneBoard/Tests/ScreenshotSessionLifecycleTests.swift
git commit -m "feat: lock screenshot selection when annotation starts"
```

- [ ] **Step 7: Package and verify the DMG**

Run: `ONEBOARD_CODESIGN_IDENTITY=- script/package_app.sh`

Expected: production build succeeds, app bundle validation succeeds, and `build/OneBoard.dmg` is created.

Run: `hdiutil verify build/OneBoard.dmg`

Expected: `checksum of "build/OneBoard.dmg" is VALID`.

- [ ] **Step 8: Perform the manual interaction checklist**

On the packaged app:

1. Frame a region at the top, center, and bottom; confirm mouse-up keeps it in place.
2. Move the region and resize from all eight handles.
3. Click rectangle, arrow, text, and mosaic in separate runs; confirm the first tool click locks the region.
4. Try dragging the image boundary after annotation starts; confirm the screenshot bounds no longer change.
5. Confirm copy/save content matches the locked region on Retina and, if available, a secondary display.

Expected: no vertical mirroring, no jump between selection and annotation, and no selection changes after lock.

---

## Plan Self-Review Checklist

- Spec coverage: coordinate separation, move, eight-way resize, restart outside selection, tool-first lock, output actions, Retina, multi-display coordinates, test/build/package/manual acceptance are each assigned to a task.
- Placeholder scan: the plan contains no deferred implementation markers; every behavior names a file, interface, command, and expected result.
- Type consistency: `ScreenshotSelectionAction` is defined once in Task 2, stored on `ScreenshotResult` in Task 3, forwarded by Task 4, and routed by Task 5.
- Scope: no changes to the executable target, database, unrelated annotation rendering, file staging, or Finder extension.
