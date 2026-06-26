import AppKit

/// 标注 ViewModel - 使用 NSEvent 监听实现流畅的拖拽和绘制
@MainActor
final class AnnotationViewModel: ObservableObject {
    @Published var annotationService: AnnotationService
    @Published var isDrawing: Bool = false
    @Published var currentPoint: CGPoint = .zero
    @Published var isTextInput: Bool = false
    @Published var textInputPoint: CGPoint = .zero
    @Published var textInputRect: CGRect = .zero

    /// 当前选中的文字标注 id（用于移动/编辑/删除）
    @Published var selectedTextLayerID: UUID?
    /// 正在编辑的文字标注 id
    @Published var editingTextLayerID: UUID?

    private weak var window: NSWindow?
    private var localMouseMonitor: Any?
    private var startPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var dragStartScreenPoint: CGPoint = .zero
    private var dragStartWindowOrigin: CGPoint = .zero
    private var isDraggingWindow: Bool = false
    private var isDraggingTextLayer: Bool = false
    private var isResizingTextLayer: Bool = false
    private var resizingTextLayerID: UUID?
    private var resizingTextHandle: TextResizeHandle?
    private var resizeStartRect: CGRect = .zero
    private var resizeStartPoint: CGPoint = .zero
    private let textResizeHitWidth: CGFloat = 8
    private var textInputCommitHandler: (() -> Void)?

    init(annotationService: AnnotationService) {
        self.annotationService = annotationService
    }

    func setWindow(_ window: NSWindow) {
        self.window = window
        setupMouseMonitor(for: window)
    }

    func setTextInputCommitHandler(_ handler: @escaping () -> Void) {
        textInputCommitHandler = handler
    }

    func closeWindow() {
        localMouseMonitor.map { NSEvent.removeMonitor($0) }
        localMouseMonitor = nil
        window?.close()
    }

    // MARK: - NSEvent 鼠标监听（比 DragGesture 更顺滑）

    private func setupMouseMonitor(for window: NSWindow) {
        localMouseMonitor.map { NSEvent.removeMonitor($0) }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === window else { return event }

            let winPoint = event.locationInWindow
            guard let contentView = window.contentView else { return event }
            let imagePoint = CGPoint(x: winPoint.x, y: contentView.bounds.height - winPoint.y)

            switch event.type {
            case .leftMouseDown:
                self.onMouseDown(at: imagePoint, event: event)
            case .leftMouseDragged:
                self.onMouseDragged(at: imagePoint, event: event)
            case .leftMouseUp:
                self.onMouseUp(at: imagePoint, event: event)
            default:
                break
            }
            return event
        }
    }

    private func onMouseDown(at point: CGPoint, event: NSEvent) {
        // 文字标注编辑中 → 不处理鼠标
        if editingTextLayerID != nil { return }
        if isTextInput {
            if !expandedTextInputRect.contains(point) {
                textInputCommitHandler?()
            }
            return
        }

        // 移动/文字模式：检查是否点中了文字标注（可拖动/编辑）
        if annotationService.selectedTool == .cursor || annotationService.selectedTool == .text {
            for layer in annotationService.layers.reversed() where layer.tool == .text {
                if let handle = textResizeHandle(at: point, in: layer.rect) {
                    selectedTextLayerID = layer.id
                    resizingTextLayerID = layer.id
                    resizingTextHandle = handle
                    resizeStartRect = layer.rect
                    resizeStartPoint = point
                    isResizingTextLayer = true
                    return
                }

                if layer.rect.contains(point) {
                    selectedTextLayerID = layer.id
                    startPoint = point
                    isDraggingTextLayer = true
                    return
                }
            }
            if annotationService.selectedTool == .cursor {
                selectedTextLayerID = nil
            }
        }

        isDrawing = true
        startPoint = point
        lastDragPoint = point
        currentPoint = point

        if annotationService.selectedTool == .cursor {
            isDraggingWindow = true
            if let window {
                dragStartScreenPoint = screenPoint(for: event, in: window)
                dragStartWindowOrigin = window.frame.origin
            }
        } else if annotationService.selectedTool == .text {
            textInputPoint = point
            let fs = annotationService.fontSize
            // 初始输入框大小随字体缩放
            let initialWidth: CGFloat = max(fs * 8, 120)
            let initialHeight: CGFloat = max(fs * 1.8, 30)
            textInputRect = CGRect(x: point.x, y: point.y, width: initialWidth, height: initialHeight)
            isTextInput = true
            isDrawing = false
        } else if annotationService.selectedTool == .number {
            annotationService.addNumber(at: point)
            isDrawing = false
            return
        }
    }

    private func onMouseDragged(at point: CGPoint, event: NSEvent) {
        if isResizingTextLayer, let layerID = resizingTextLayerID {
            resizeTextLayer(id: layerID, to: point)
            return
        }

        // 拖拽文字标注
        if isDraggingTextLayer, let layerID = selectedTextLayerID,
           let index = annotationService.layers.firstIndex(where: { $0.id == layerID }) {
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            var layer = annotationService.layers[index]
            let origRect = layer.rect
            layer.rect.origin = CGPoint(x: origRect.origin.x + dx, y: origRect.origin.y + dy)
            annotationService.layers[index] = layer
            startPoint = point
            return
        }

        if isDraggingWindow {
            if let window {
                let currentScreenPoint = screenPoint(for: event, in: window)
                let dx = currentScreenPoint.x - dragStartScreenPoint.x
                let dy = currentScreenPoint.y - dragStartScreenPoint.y
                var frame = window.frame
                frame.origin.x = dragStartWindowOrigin.x + dx
                frame.origin.y = dragStartWindowOrigin.y + dy
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    window.setFrameOrigin(frame.origin)
                }
            }
            return
        }

        guard isDrawing else { return }
        currentPoint = point
        updateCurrentDrawing()
    }

    private func onMouseUp(at point: CGPoint, event: NSEvent) {
        if isResizingTextLayer {
            resizeTextLayer(id: resizingTextLayerID, to: point)
            isResizingTextLayer = false
            resizingTextLayerID = nil
            resizingTextHandle = nil
            return
        }

        // 单击选中文字标注（双击编辑由外部处理）
        if selectedTextLayerID != nil, !isDraggingTextLayer {
            // 仅选中，不拖拽
        }
        if isDraggingTextLayer {
            isDraggingTextLayer = false
            return
        }

        isDraggingWindow = false
        lastDragPoint = .zero
        dragStartScreenPoint = .zero
        dragStartWindowOrigin = .zero

        guard isDrawing else { return }
        currentPoint = point
        isDrawing = false
        commitDrawing()
    }

    /// 双击文字标注进入编辑
    func enterTextEdit() {
        guard let layerID = selectedTextLayerID else { return }
        editingTextLayerID = layerID
    }

    // MARK: - 文字输入

    func commitText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isTextInput, !trimmedText.isEmpty else {
            isTextInput = false
            return
        }
        annotationService.addText(in: textInputRect, text: trimmedText)
        selectedTextLayerID = nil
        isTextInput = false
    }

    func cancelTextInput() {
        isTextInput = false
    }

    func commitEditText(_ text: String) {
        guard let id = editingTextLayerID, !text.isEmpty else {
            editingTextLayerID = nil
            return
        }
        annotationService.updateTextLayer(id: id, text: text)
        editingTextLayerID = nil
    }

    func cancelEditText() {
        editingTextLayerID = nil
    }

    func deleteSelectedTextLayer() {
        guard let id = selectedTextLayerID else { return }
        annotationService.removeLayer(id: id)
        selectedTextLayerID = nil
    }

    // MARK: - 绘制

    private func updateCurrentDrawing() {
        let rect = createRect(from: startPoint, to: currentPoint)

        switch annotationService.selectedTool {
        case .cursor, .text, .number:
            annotationService.currentDrawingLayer = nil
        case .rectangle:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .rectangle, rect: rect,
                color: annotationService.selectedColor, lineWidth: annotationService.lineWidth
            )
        case .line:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .line, rect: rect,
                color: annotationService.selectedColor, lineWidth: annotationService.lineWidth,
                startPoint: startPoint, endPoint: currentPoint
            )
        case .ellipse:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .ellipse, rect: rect,
                color: annotationService.selectedColor, lineWidth: annotationService.lineWidth
            )
        case .arrow:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .arrow, rect: rect,
                color: annotationService.selectedColor, lineWidth: annotationService.lineWidth,
                startPoint: startPoint, endPoint: currentPoint
            )
        case .mosaic:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .mosaic, rect: rect,
                color: annotationService.selectedColor, lineWidth: 0
            )
        }
    }

    private func commitDrawing() {
        let rect = createRect(from: startPoint, to: currentPoint)
        guard rect.width > 3 || rect.height > 3 else { return }

        switch annotationService.selectedTool {
        case .cursor, .text, .number: break
        case .rectangle: annotationService.addRectangle(rect)
        case .ellipse: annotationService.addEllipse(rect)
        case .line: annotationService.addLine(from: startPoint, to: currentPoint)
        case .arrow: annotationService.addArrow(from: startPoint, to: currentPoint)
        case .mosaic: annotationService.addMosaic(rect)
        }

        annotationService.currentDrawingLayer = nil
    }

    func undo() {
        annotationService.undo()
    }

    func redo() {
        annotationService.redo()
    }

    func selectTool(forNumberKey key: UInt16) -> Bool {
        let mapping: [UInt16: AnnotationTool] = [
            18: .cursor,
            19: .rectangle,
            20: .ellipse,
            21: .arrow,
            23: .line,
            22: .text,
            26: .number,
            28: .mosaic,
        ]
        guard let tool = mapping[key] else { return false }
        annotationService.selectedTool = tool
        return true
    }

    func cycleColorBackward() {
        annotationService.cyclePresetColorBackward()
    }

    func incrementStyleValue() {
        annotationService.incrementStyleValue()
    }

    private func createRect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
    }

    private var expandedTextInputRect: CGRect {
        textInputRect.insetBy(dx: -textResizeHitWidth, dy: -textResizeHitWidth)
    }

    private func textResizeHandle(at point: CGPoint, in rect: CGRect) -> TextResizeHandle? {
        let handles = TextResizeHandle.allCases.map { handle in
            (handle, handle.hitRect(in: rect, hitWidth: textResizeHitWidth))
        }
        return handles.first { $0.1.contains(point) }?.0
    }

    private func resizeTextLayer(id: UUID?, to point: CGPoint) {
        guard let id, let resizingTextHandle else { return }
        let minSize = CGSize(width: 40, height: 24)
        let rect = resizingTextHandle.resizedRect(
            from: resizeStartRect,
            startPoint: resizeStartPoint,
            currentPoint: point,
            minSize: minSize
        )
        annotationService.updateTextLayer(id: id, rect: rect)
    }

    private func screenPoint(for event: NSEvent, in window: NSWindow) -> CGPoint {
        window.convertPoint(toScreen: event.locationInWindow)
    }
}

private enum TextResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    func hitRect(in rect: CGRect, hitWidth: CGFloat) -> CGRect {
        let center: CGPoint
        switch self {
        case .topLeft: center = CGPoint(x: rect.minX, y: rect.minY)
        case .top: center = CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: center = CGPoint(x: rect.maxX, y: rect.minY)
        case .right: center = CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: center = CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: center = CGPoint(x: rect.minX, y: rect.maxY)
        case .left: center = CGPoint(x: rect.minX, y: rect.midY)
        }
        return CGRect(
            x: center.x - hitWidth,
            y: center.y - hitWidth,
            width: hitWidth * 2,
            height: hitWidth * 2
        )
    }

    func resizedRect(from rect: CGRect, startPoint: CGPoint, currentPoint: CGPoint, minSize: CGSize) -> CGRect {
        let dx = currentPoint.x - startPoint.x
        let dy = currentPoint.y - startPoint.y
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch self {
        case .topLeft:
            minX += dx
            minY += dy
        case .top:
            minY += dy
        case .topRight:
            maxX += dx
            minY += dy
        case .right:
            maxX += dx
        case .bottomRight:
            maxX += dx
            maxY += dy
        case .bottom:
            maxY += dy
        case .bottomLeft:
            minX += dx
            maxY += dy
        case .left:
            minX += dx
        }

        if maxX - minX < minSize.width {
            if adjustsLeftEdge {
                minX = maxX - minSize.width
            } else {
                maxX = minX + minSize.width
            }
        }
        if maxY - minY < minSize.height {
            if adjustsTopEdge {
                minY = maxY - minSize.height
            } else {
                maxY = minY + minSize.height
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var adjustsLeftEdge: Bool {
        self == .topLeft || self == .bottomLeft || self == .left
    }

    private var adjustsTopEdge: Bool {
        self == .topLeft || self == .top || self == .topRight
    }
}
