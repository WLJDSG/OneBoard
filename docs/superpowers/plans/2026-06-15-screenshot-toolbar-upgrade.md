# Screenshot Toolbar Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the screenshot annotation toolbar with numbered markers, grouped controls, annotation-window shortcuts, redo, direct Desktop save, and screenshot size display.

**Architecture:** Keep the existing post-capture annotation window and separate floating toolbar. Put annotation state and history in `AnnotationService`, mouse interactions in `AnnotationViewModel`, keyboard routing in `AnnotationCanvasView`, and grouped toolbar UI in `AnnotationToolbarView`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, Swift Package Manager.

---

## File Structure

- Modify `OneBoard/Modules/Screenshot/Models/AnnotationLayer.swift`
  - Add `.number`.
  - Add `numberValue`.
  - Add display name and SF Symbol mapping.

- Modify `OneBoard/Modules/Screenshot/Services/AnnotationService.swift`
  - Add redo stack.
  - Add tool-aware style state.
  - Add numbered marker creation and rendering.
  - Add color cycling and style increment helpers for shortcuts.
  - Add configurable mosaic block size.

- Modify `OneBoard/Modules/Screenshot/ViewModels/AnnotationViewModel.swift`
  - Add numbered-marker click behavior.
  - Add command methods for undo, redo, tool selection, color cycling, and style increment.

- Modify `OneBoard/Modules/Screenshot/Views/AnnotationCanvasView.swift`
  - Route keyboard shortcuts only while the annotation window is active.
  - Avoid shortcut handling while text input/editing is active.
  - Show screenshot pixel size overlay.
  - Preview numbered marker layers.

- Modify `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`
  - Rebuild toolbar as grouped controls.
  - Add redo button.
  - Add style controls and shortcut tooltips.
  - Route save to direct Desktop save.

- Modify `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
  - Add direct Desktop save helper, or update existing save path if this file already owns saving.

- Modify `OneBoard/Tests/AnnotationServiceTests.swift`
  - Add tests for numbered marker incrementing, undo/redo, redo clearing, and number rendering.

---

### Task 1: Extend Annotation Layer Model

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Models/AnnotationLayer.swift`
- Test: `OneBoard/Tests/AnnotationServiceTests.swift`

- [ ] **Step 1: Add a failing model-level test for numbered marker creation**

Append this test inside `AnnotationServiceTests`:

```swift
func testNumberedMarkersIncrementFromOne() {
    let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
    let service = AnnotationService(baseImage: image)

    service.addNumber(at: CGPoint(x: 20, y: 20))
    service.addNumber(at: CGPoint(x: 50, y: 50))

    XCTAssertEqual(service.layers.map(\.tool), [.number, .number])
    XCTAssertEqual(service.layers.map(\.numberValue), [1, 2])
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests/testNumberedMarkersIncrementFromOne
```

Expected: FAIL because `.number`, `numberValue`, and `addNumber(at:)` do not exist yet.

- [ ] **Step 3: Update `AnnotationLayer.swift`**

Change `AnnotationTool` and `AnnotationLayer` to include number support:

```swift
enum AnnotationTool: String, CaseIterable {
    case cursor
    case rectangle
    case ellipse
    case arrow
    case line
    case text
    case number
    case mosaic

    var displayName: String {
        switch self {
        case .cursor: return "移动"
        case .rectangle: return "矩形"
        case .ellipse: return "圆形"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .text: return "文字"
        case .number: return "编号"
        case .mosaic: return "打码"
        }
    }

    var iconName: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .text: return "character.textbox"
        case .number: return "1.circle"
        case .mosaic: return "checkerboard.rectangle"
        }
    }
}
```

Add `numberValue` to the layer:

```swift
struct AnnotationLayer: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var rect: CGRect
    var color: NSColor
    var text: String?
    var numberValue: Int?
    var fontSize: CGFloat
    var lineWidth: CGFloat
    var startPoint: CGPoint?
    var endPoint: CGPoint?

    init(
        tool: AnnotationTool,
        rect: CGRect,
        color: NSColor = .systemRed,
        text: String? = nil,
        numberValue: Int? = nil,
        fontSize: CGFloat = 18,
        lineWidth: CGFloat = 2.0,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil
    ) {
        self.tool = tool
        self.rect = rect
        self.color = color
        self.text = text
        self.numberValue = numberValue
        self.fontSize = fontSize
        self.lineWidth = lineWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}
```

- [ ] **Step 4: Add minimal service creation support**

In `AnnotationService.swift`, add:

```swift
@Published var numberBadgeSize: CGFloat = 28

func addNumber(at point: CGPoint) {
    let nextNumber = (layers.compactMap(\.numberValue).max() ?? 0) + 1
    let size = numberBadgeSize
    let rect = CGRect(
        x: point.x - size / 2,
        y: point.y - size / 2,
        width: size,
        height: size
    )
    let layer = AnnotationLayer(
        tool: .number,
        rect: rect,
        color: selectedColor,
        numberValue: nextNumber,
        fontSize: max(12, size * 0.52),
        lineWidth: lineWidth
    )
    layers.append(layer)
}
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests/testNumberedMarkersIncrementFromOne
```

Expected: PASS.

---

### Task 2: Add Undo And Redo History

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Services/AnnotationService.swift`
- Modify: `OneBoard/Tests/AnnotationServiceTests.swift`

- [ ] **Step 1: Add failing undo/redo tests**

Append these tests inside `AnnotationServiceTests`:

```swift
func testUndoAndRedoRestoreLastLayer() {
    let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
    let service = AnnotationService(baseImage: image)

    service.addRectangle(CGRect(x: 1, y: 2, width: 30, height: 40))
    service.addNumber(at: CGPoint(x: 60, y: 60))

    service.undo()
    XCTAssertEqual(service.layers.count, 1)
    XCTAssertTrue(service.canRedo)

    service.redo()
    XCTAssertEqual(service.layers.count, 2)
    XCTAssertEqual(service.layers.last?.tool, .number)
    XCTAssertEqual(service.layers.last?.numberValue, 1)
}

func testAddingLayerAfterUndoClearsRedo() {
    let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
    let service = AnnotationService(baseImage: image)

    service.addRectangle(CGRect(x: 1, y: 2, width: 30, height: 40))
    service.addEllipse(CGRect(x: 10, y: 10, width: 20, height: 20))
    service.undo()
    XCTAssertTrue(service.canRedo)

    service.addLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40))

    XCTAssertFalse(service.canRedo)
    service.redo()
    XCTAssertEqual(service.layers.map(\.tool), [.rectangle, .line])
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests
```

Expected: FAIL because `canRedo` and `redo()` do not exist.

- [ ] **Step 3: Add redo state and mutation helpers**

In `AnnotationService.swift`, add:

```swift
@Published private(set) var redoLayers: [AnnotationLayer] = []

var canUndo: Bool {
    !layers.isEmpty
}

var canRedo: Bool {
    !redoLayers.isEmpty
}

private func appendLayer(_ layer: AnnotationLayer) {
    layers.append(layer)
    redoLayers.removeAll()
}
```

Update every `layers.append(layer)` inside add methods to:

```swift
appendLayer(layer)
```

- [ ] **Step 4: Replace undo and add redo**

Replace `undo()` with:

```swift
func undo() {
    guard let layer = layers.popLast() else { return }
    redoLayers.append(layer)
}
```

Add:

```swift
func redo() {
    guard let layer = redoLayers.popLast() else { return }
    layers.append(layer)
}
```

Update mutation methods that remove or edit layers:

```swift
func removeLayer(id: UUID) {
    layers.removeAll { $0.id == id }
    redoLayers.removeAll()
}

func removeAll() {
    layers.removeAll()
    redoLayers.removeAll()
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests
```

Expected: PASS.

---

### Task 3: Render And Preview Numbered Markers

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Services/AnnotationService.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationCanvasView.swift`
- Modify: `OneBoard/Tests/AnnotationServiceTests.swift`

- [ ] **Step 1: Add a failing render test for numbered markers**

Append this test inside `AnnotationServiceTests`:

```swift
func testRenderNumberedMarkerDrawsColoredBadge() throws {
    let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
    let service = AnnotationService(baseImage: image)
    service.selectedColor = .systemBlue
    service.addNumber(at: CGPoint(x: 50, y: 50))

    let rendered = service.renderToImage(baseImage: image, displaySize: image.size)
    let rep = try XCTUnwrap(rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first)

    let center = try XCTUnwrap(rep.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB))
    XCTAssertGreaterThan(center.blueComponent, 0.45)
    XCTAssertLessThan(center.redComponent, 0.45)
}
```

- [ ] **Step 2: Run the focused render test and verify failure**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests/testRenderNumberedMarkerDrawsColoredBadge
```

Expected: FAIL because `.number` is not rendered.

- [ ] **Step 3: Add number drawing in `AnnotationService`**

In `drawLayer`, add:

```swift
case .number:
    drawNumberBadge(layer, in: ctx, canvasHeight: canvasHeight)
```

Add helper methods:

```swift
private func drawNumberBadge(_ layer: AnnotationLayer, in ctx: CGContext, canvasHeight: CGFloat) {
    let number = layer.numberValue ?? 0
    ctx.setFillColor(layer.color.cgColor)
    ctx.fillEllipse(in: layer.rect)

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.setLineWidth(max(1, layer.lineWidth))
    ctx.strokeEllipse(in: layer.rect.insetBy(dx: 0.75, dy: 0.75))

    let textColor = contrastingTextColor(for: layer.color)
    let font = NSFont.systemFont(ofSize: layer.fontSize, weight: .bold)
    let text = "\(number)" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor
    ]
    let textSize = text.size(withAttributes: attrs)
    let drawRect = CGRect(
        x: layer.rect.midX - textSize.width / 2,
        y: canvasHeight - layer.rect.midY - textSize.height / 2,
        width: textSize.width,
        height: textSize.height
    )

    ctx.saveGState()
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: 0, y: -canvasHeight)
    text.draw(in: drawRect, withAttributes: attrs)
    ctx.restoreGState()
}

private func contrastingTextColor(for color: NSColor) -> NSColor {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return .white }
    let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    return luminance > 0.62 ? .black : .white
}
```

- [ ] **Step 4: Add SwiftUI preview for number layers**

In `AnnotationLayerView.layerContent`, add:

```swift
case .number:
    numberLayerView
```

Add:

```swift
private var numberLayerView: some View {
    let textColor = readableTextColor(for: layer.color)
    return ZStack {
        Circle()
            .fill(Color(nsColor: layer.color))
        Circle()
            .stroke(Color.white.opacity(0.85), lineWidth: max(1, layer.lineWidth))
        Text("\(layer.numberValue ?? 0)")
            .font(.system(size: layer.fontSize, weight: .bold))
            .foregroundColor(textColor)
    }
    .frame(width: layer.rect.width, height: layer.rect.height)
    .position(x: layer.rect.midX, y: layer.rect.midY)
    .allowsHitTesting(false)
}

private func readableTextColor(for color: NSColor) -> Color {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return .white }
    let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    return luminance > 0.62 ? .black : .white
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests
```

Expected: PASS.

---

### Task 4: Add Tool-Aware Style Controls

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Services/AnnotationService.swift`
- Modify: `OneBoard/Tests/AnnotationServiceTests.swift`

- [ ] **Step 1: Add failing tests for style helpers**

Append:

```swift
func testCyclePresetColorMovesThroughPalette() {
    let service = AnnotationService()
    service.selectedColor = .systemRed

    service.cyclePresetColorBackward()

    XCTAssertEqual(service.selectedColor, .white)
}

func testIncrementStyleValueUsesSelectedTool() {
    let service = AnnotationService()

    service.selectedTool = .rectangle
    service.lineWidth = 2
    service.incrementStyleValue()
    XCTAssertEqual(service.lineWidth, 3)

    service.selectedTool = .text
    service.fontSize = 18
    service.incrementStyleValue()
    XCTAssertEqual(service.fontSize, 20)

    service.selectedTool = .mosaic
    service.mosaicBlockSize = 6
    service.incrementStyleValue()
    XCTAssertEqual(service.mosaicBlockSize, 8)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests/testCyclePresetColorMovesThroughPalette
cd OneBoard && swift test --filter AnnotationServiceTests/testIncrementStyleValueUsesSelectedTool
```

Expected: FAIL because helpers and style properties do not exist.

- [ ] **Step 3: Add style properties and preset palette**

In `AnnotationService`:

```swift
let presetColors: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen,
    .systemTeal, .systemBlue, .systemPurple, .systemPink,
    .black, .white
]

@Published var fontSize: CGFloat = 18
@Published var mosaicBlockSize: CGFloat = 6
```

- [ ] **Step 4: Update text, number, and mosaic creation to use style state**

Update `addText(in:text:fontSize:)` default handling:

```swift
func addText(in rect: CGRect, text: String, fontSize: CGFloat? = nil) {
    let layer = AnnotationLayer(
        tool: .text,
        rect: rect,
        color: selectedColor,
        text: text,
        fontSize: fontSize ?? self.fontSize
    )
    appendLayer(layer)
}
```

Update call sites that pass `fontSize:` explicitly if Swift complains about optional default migration.

Update `addMosaic`:

```swift
func addMosaic(_ rect: CGRect) {
    let layer = AnnotationLayer(
        tool: .mosaic,
        rect: rect,
        color: .clear,
        lineWidth: mosaicBlockSize
    )
    appendLayer(layer)
}
```

- [ ] **Step 5: Add style helper methods**

```swift
func cyclePresetColorBackward() {
    guard let index = presetColors.firstIndex(where: { $0.isEqual(selectedColor) }) else {
        selectedColor = presetColors.last ?? .systemRed
        return
    }
    let previousIndex = index == 0 ? presetColors.count - 1 : index - 1
    selectedColor = presetColors[previousIndex]
}

func incrementStyleValue() {
    switch selectedTool {
    case .cursor:
        break
    case .rectangle, .ellipse, .arrow, .line:
        lineWidth = min(lineWidth + 1, 12)
    case .text:
        fontSize = min(fontSize + 2, 48)
    case .number:
        numberBadgeSize = min(numberBadgeSize + 2, 48)
    case .mosaic:
        mosaicBlockSize = min(mosaicBlockSize + 2, 24)
    }
}

func decrementStyleValue() {
    switch selectedTool {
    case .cursor:
        break
    case .rectangle, .ellipse, .arrow, .line:
        lineWidth = max(lineWidth - 1, 1)
    case .text:
        fontSize = max(fontSize - 2, 12)
    case .number:
        numberBadgeSize = max(numberBadgeSize - 2, 20)
    case .mosaic:
        mosaicBlockSize = max(mosaicBlockSize - 2, 4)
    }
}
```

- [ ] **Step 6: Make mosaic rendering use layer lineWidth as block size**

Change `drawMosaic` signature:

```swift
private func drawMosaic(in rect: CGRect, blockSize: CGFloat, context ctx: CGContext) {
    let cell = max(4, blockSize)
    ...
}
```

Call it with:

```swift
drawMosaic(in: layer.rect, blockSize: layer.lineWidth, context: ctx)
```

- [ ] **Step 7: Run tests**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests
```

Expected: PASS.

---

### Task 5: Wire Mouse And Keyboard Commands

**Files:**
- Modify: `OneBoard/Modules/Screenshot/ViewModels/AnnotationViewModel.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationCanvasView.swift`

- [ ] **Step 1: Add numbered marker mouse behavior**

In `AnnotationViewModel.onMouseDown`, after text handling and before setting `isDrawing = true`, add:

```swift
if annotationService.selectedTool == .number {
    annotationService.addNumber(at: point)
    isDrawing = false
    return
}
```

In `updateCurrentDrawing` and `commitDrawing`, add `.number` alongside `.cursor` and `.text` as a non-drag drawing tool:

```swift
case .cursor, .text, .number:
    annotationService.currentDrawingLayer = nil
```

and:

```swift
case .cursor, .text, .number:
    break
```

- [ ] **Step 2: Add command helpers to `AnnotationViewModel`**

Add:

```swift
func selectTool(forNumberKey key: UInt16) -> Bool {
    let mapping: [UInt16: AnnotationTool] = [
        18: .cursor,
        19: .rectangle,
        20: .ellipse,
        21: .arrow,
        23: .line,
        22: .text,
        26: .number,
        28: .mosaic
    ]
    guard let tool = mapping[key] else { return false }
    annotationService.selectedTool = tool
    return true
}

func redo() {
    annotationService.redo()
}

func cycleColorBackward() {
    annotationService.cyclePresetColorBackward()
}

func incrementStyleValue() {
    annotationService.incrementStyleValue()
}
```

Key codes above are macOS ANSI number row codes for `1` through `8`.

- [ ] **Step 3: Add keyboard routing in `AnnotationCanvasView`**

Replace the existing key monitor body with a helper call:

```swift
keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
    handleKeyboardEvent(event)
}
```

Add this helper in `AnnotationCanvasView`:

```swift
private func handleKeyboardEvent(_ event: NSEvent) -> NSEvent? {
    if event.type == .flagsChanged {
        return handleFlagsChanged(event)
    }

    if viewModel.isTextInput || viewModel.editingTextLayerID != nil {
        if event.keyCode == 53 {
            if viewModel.isTextInput {
                viewModel.cancelTextInput()
            } else {
                viewModel.cancelEditText()
            }
            return nil
        }
        return event
    }

    if event.modifierFlags.contains(.command), event.keyCode == 6 {
        if event.modifierFlags.contains(.shift) {
            viewModel.redo()
        } else {
            viewModel.undo()
        }
        return nil
    }

    if event.modifierFlags.contains(.command), event.keyCode == 1 {
        let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: baseImage.size)
        onSave(rendered)
        return nil
    }

    if event.keyCode == 36 {
        let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: baseImage.size)
        onCopy(rendered)
        return nil
    }

    if event.keyCode == 53 {
        onClose()
        return nil
    }

    if event.keyCode == 51, viewModel.selectedTextLayerID != nil {
        viewModel.deleteSelectedTextLayer()
        return nil
    }

    if viewModel.selectTool(forNumberKey: event.keyCode) {
        return nil
    }

    return event
}
```

Add:

```swift
private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    guard !viewModel.isTextInput, viewModel.editingTextLayerID == nil else { return event }

    switch event.keyCode {
    case 58:
        viewModel.cycleColorBackward()
        return nil
    case 61:
        viewModel.incrementStyleValue()
        return nil
    default:
        return event
    }
}
```

Key codes `58` and `61` are left and right Option on common macOS keyboards. If local verification shows swapped codes on the target machine, update the mapping in this helper.

- [ ] **Step 4: Run build**

Run:

```bash
cd OneBoard && swift build
```

Expected: build succeeds.

---

### Task 6: Rebuild Toolbar UI Into Groups

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`

- [ ] **Step 1: Replace local preset colors with service palette**

Remove local `presetColors` or change color loops to use:

```swift
annotationService.presetColors
```

- [ ] **Step 2: Add toolbar group structure**

Keep `body` as:

```swift
var body: some View {
    HStack(spacing: 8) {
        toolGroup
        styleGroup
        historyGroup
        outputGroup
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 14)
            .fill(.ultraThinMaterial)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
        colorPickerPopover
    }
}
```

- [ ] **Step 3: Add shortcut-aware tool buttons**

Add:

```swift
private let toolShortcuts: [AnnotationTool: String] = [
    .cursor: "1",
    .rectangle: "2",
    .ellipse: "3",
    .arrow: "4",
    .line: "5",
    .text: "6",
    .number: "7",
    .mosaic: "8"
]
```

Update `toolButton(_:)` help:

```swift
.help("\(tool.displayName) \(toolShortcuts[tool] ?? "")")
```

- [ ] **Step 4: Add style group**

Add:

```swift
private var styleGroup: some View {
    HStack(spacing: 7) {
        ForEach(annotationService.presetColors, id: \.self) { color in
            colorSwatch(color)
        }

        Divider().frame(height: 22)

        Button(action: { annotationService.decrementStyleValue() }) {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help("减小样式")

        Text(styleValueText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .frame(minWidth: 34)

        Button(action: { annotationService.incrementStyleValue() }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .help("增大样式 Right Option")

        Button(action: { showColorPicker.toggle() }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("更多颜色")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.045)))
}

private var styleValueText: String {
    switch annotationService.selectedTool {
    case .cursor:
        return "-"
    case .rectangle, .ellipse, .arrow, .line:
        return "\(Int(annotationService.lineWidth))"
    case .text:
        return "\(Int(annotationService.fontSize))"
    case .number:
        return "\(Int(annotationService.numberBadgeSize))"
    case .mosaic:
        return "\(Int(annotationService.mosaicBlockSize))"
    }
}
```

- [ ] **Step 5: Add history group**

Add:

```swift
private var historyGroup: some View {
    HStack(spacing: 6) {
        iconActionButton("撤销 Cmd+Z", icon: "arrow.uturn.backward") {
            viewModel.undo()
        }
        .disabled(!annotationService.canUndo)

        iconActionButton("重做 Cmd+Shift+Z", icon: "arrow.uturn.forward") {
            viewModel.redo()
        }
        .disabled(!annotationService.canRedo)
    }
    .padding(4)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.045)))
}
```

- [ ] **Step 6: Rename action row to output group and keep actions**

Rename `actionButtonsRow` to `outputGroup`, and remove undo from it because undo/redo live in `historyGroup`.

The output group must include:

```swift
iconActionButton("保存到桌面 Cmd+S", icon: "square.and.arrow.down") { ... }
iconActionButton("贴图", icon: "pin") { ... }
iconActionButton("OCR", icon: "text.viewfinder") { ... }
iconActionButton("完成 Enter", icon: "checkmark", prominent: true) { ... }
iconActionButton("关闭 Esc", icon: "xmark", muted: true) { ... }
```

- [ ] **Step 7: Run build**

Run:

```bash
cd OneBoard && swift build
```

Expected: build succeeds.

---

### Task 7: Direct Desktop Save And Size Display

**Files:**
- Modify: `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationCanvasView.swift`
- Modify: `OneBoard/Tests/AnnotationServiceTests.swift`

- [ ] **Step 1: Add pixel-size helper test**

Append:

```swift
func testRenderedImagePixelSizeHelperUsesBitmapPixels() {
    let image = makeImage(points: CGSize(width: 100, height: 50), pixels: CGSize(width: 200, height: 100))

    XCTAssertEqual(AnnotationService.pixelSizeDescription(for: image), "200 x 100")
}
```

- [ ] **Step 2: Expose pixel size description**

In `AnnotationService`, make a public helper:

```swift
static func pixelSizeDescription(for image: NSImage) -> String {
    let pixelSize = pixelSize(for: image)
    return "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
}
```

Change `private static func pixelSize(for image: NSImage)` to:

```swift
static func pixelSize(for image: NSImage) -> CGSize
```

- [ ] **Step 3: Add size overlay in `AnnotationCanvasView`**

Inside the outer `ZStack`, above text overlays, add:

```swift
VStack {
    HStack {
        Text(AnnotationService.pixelSizeDescription(for: baseImage))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        Spacer()
    }
    Spacer()
}
.padding(8)
.allowsHitTesting(false)
```

- [ ] **Step 4: Add Desktop save helper**

In `ScreenshotViewModel`, add:

```swift
func saveRenderedImageToDesktop(_ image: NSImage, date: Date = Date()) {
    guard let data = image.pngData else {
        print("[ScreenshotViewModel] PNG 数据生成失败")
        return
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let fileName = "OneBoard Screenshot \(formatter.string(from: date)).png"

    let desktopURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)
    let fileURL = desktopURL.appendingPathComponent(fileName)

    do {
        try data.write(to: fileURL, options: .atomic)
        print("[ScreenshotViewModel] 截图已保存到桌面: \(fileURL.path)")
    } catch {
        print("[ScreenshotViewModel] 保存到桌面失败: \(error)")
        saveToFile(image)
    }
}
```

If `saveToFile(_:)` is private and this helper lives next to it, the fallback can call it directly.

- [ ] **Step 5: Route toolbar save to Desktop**

In `AnnotationToolbarView`, change save action to:

```swift
iconActionButton("保存到桌面 Cmd+S", icon: "square.and.arrow.down") {
    let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
    ScreenshotViewModel.shared.saveRenderedImageToDesktop(rendered)
}
```

If retaining the `onSave` closure is preferred, update `ScreenshotViewModel.showAnnotationWindow` so `onSave` calls `saveRenderedImageToDesktop`.

- [ ] **Step 6: Route keyboard save to Desktop**

Ensure the `Cmd+S` path in `AnnotationCanvasView` calls the same `onSave(rendered)` closure used by the toolbar, and ensure that closure now saves to Desktop.

- [ ] **Step 7: Run tests and build**

Run:

```bash
cd OneBoard && swift test --filter AnnotationServiceTests
cd OneBoard && swift build
```

Expected: tests pass and build succeeds.

---

### Task 8: Final Verification And Documentation

**Files:**
- Modify: `docs/开发步骤/README.md`
- Modify: `开发日志/2026-06/2026-06-15.md`

- [ ] **Step 1: Run full test suite**

Run:

```bash
cd OneBoard && swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run required build verification**

Run:

```bash
cd OneBoard && swift build
```

Expected: build succeeds.

- [ ] **Step 3: Manually verify screenshot toolbar**

Run the app using the repo's normal workflow, then verify:

```text
1 selects Move
2 selects Rectangle
3 selects Ellipse
4 selects Arrow
5 selects Line
6 selects Text
7 selects Number
8 selects Mosaic
Left Option cycles color backward
Right Option increases the active style value
Cmd+Z undoes
Cmd+Shift+Z redoes
Enter completes and copies
Esc closes
Cmd+S saves a PNG to ~/Desktop
OCR still opens the OCR bubble
Pin still creates a pinned screenshot
Size label is visible but not rendered into output image
```

- [ ] **Step 4: Update development steps**

Add a new completed item under the screenshot experience section in `docs/开发步骤/README.md`:

```markdown
10. ✅ 升级截图标注工具栏：数字键切换工具、编号标注、样式快捷键、撤销/重做、桌面直存和尺寸显示
```

- [ ] **Step 5: Update development log**

Append to `开发日志/2026-06/2026-06-15.md`:

```markdown
## 截图工具栏升级

- 完成截图标注工具栏规划与实现。
- 新增数字键快速切换标注工具。
- 新增编号标注、撤销/重做、样式快捷键、尺寸显示和保存到桌面。
- 已通过 `swift test` 和 `swift build` 验证。
```

- [ ] **Step 6: Commit if git write permissions are available**

Run:

```bash
git status --short
git add docs/superpowers/specs/2026-06-15-screenshot-toolbar-design.md docs/superpowers/plans/2026-06-15-screenshot-toolbar-upgrade.md OneBoard/Modules/Screenshot OneBoard/Tests/AnnotationServiceTests.swift docs/开发步骤/README.md 开发日志/2026-06/2026-06-15.md
git commit -m "feat: upgrade screenshot annotation toolbar"
```

Expected: commit succeeds when the environment allows writing to `.git`. If the sandbox blocks `.git/index.lock`, leave the working tree changes in place and report that staging/commit was blocked by permissions.

---

## Self-Review

Spec coverage:

- Number-key tool switching is covered by Tasks 5 and 8.
- Left/right Option style shortcuts are covered by Tasks 4, 5, and 8.
- Numbered markers are covered by Tasks 1, 3, and 8.
- Undo/redo is covered by Task 2.
- Grouped toolbar UI is covered by Task 6.
- Direct Desktop save is covered by Task 7.
- Screenshot size display is covered by Task 7.
- OCR and pin remain in the toolbar and are manually verified in Task 8.

Placeholder scan:

- No task contains TBD or deferred implementation placeholders.
- Phase 2 custom selection overlay is intentionally outside this plan.

Type consistency:

- `numberValue`, `numberBadgeSize`, `mosaicBlockSize`, `fontSize`, `canUndo`, `canRedo`, `redo()`, `incrementStyleValue()`, and `cyclePresetColorBackward()` are introduced before later tasks reference them.
