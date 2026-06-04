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
    private var resizeStartRect: CGRect = .zero
    private var resizeStartPoint: CGPoint = .zero
    private let textResizeHitWidth: CGFloat = 8

    init(annotationService: AnnotationService) {
        self.annotationService = annotationService
    }

    func setWindow(_ window: NSWindow) {
        self.window = window
        setupMouseMonitor(for: window)
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
        if isTextInput { return }

        // Cursor 模式：检查是否点中了文字标注（可拖动/编辑）
        if annotationService.selectedTool == .cursor {
            for layer in annotationService.layers where layer.tool == .text {
                if layer.rect.contains(point) {
                    selectedTextLayerID = layer.id
                    if isTextResizeHandleHit(point, in: layer.rect) {
                        resizingTextLayerID = layer.id
                        resizeStartRect = layer.rect
                        resizeStartPoint = point
                        isResizingTextLayer = true
                    } else {
                        startPoint = point
                        isDraggingTextLayer = true
                    }
                    return
                }
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
            textInputRect = CGRect(x: point.x, y: point.y, width: 140, height: 42)
            isTextInput = true
            isDrawing = false
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
        case .cursor, .text:
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
        case .cursor, .text: break
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

    private func createRect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
    }

    private func isTextResizeHandleHit(_ point: CGPoint, in rect: CGRect) -> Bool {
        let handleRect = CGRect(
            x: rect.maxX - textResizeHitWidth,
            y: rect.maxY - textResizeHitWidth,
            width: textResizeHitWidth * 2,
            height: textResizeHitWidth * 2
        )
        return handleRect.contains(point)
    }

    private func resizeTextLayer(id: UUID?, to point: CGPoint) {
        guard let id else { return }
        let minSize = CGSize(width: 40, height: 24)
        let width = max(minSize.width, resizeStartRect.width + point.x - resizeStartPoint.x)
        let height = max(minSize.height, resizeStartRect.height + point.y - resizeStartPoint.y)
        let rect = CGRect(
            x: resizeStartRect.minX,
            y: resizeStartRect.minY,
            width: width,
            height: height
        )
        annotationService.updateTextLayer(id: id, rect: rect)
    }

    private func screenPoint(for event: NSEvent, in window: NSWindow) -> CGPoint {
        window.convertPoint(toScreen: event.locationInWindow)
    }
}
