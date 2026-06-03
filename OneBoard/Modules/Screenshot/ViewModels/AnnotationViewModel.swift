import AppKit

/// 标注 ViewModel
@MainActor
final class AnnotationViewModel: ObservableObject {
    @Published var annotationService: AnnotationService
    @Published var isDrawing: Bool = false
    @Published var startPoint: CGPoint = .zero
    @Published var currentPoint: CGPoint = .zero
    @Published var isTextInput: Bool = false

    private weak var window: NSWindow?
    private var lastDragPoint: CGPoint = .zero

    init(annotationService: AnnotationService) {
        self.annotationService = annotationService
    }

    func setWindow(_ window: NSWindow) {
        self.window = window
    }

    func closeWindow() {
        window?.close()
    }

    // MARK: - 鼠标/拖拽处理

    func startDrawing(at point: CGPoint) {
        isDrawing = true
        if annotationService.selectedTool == .cursor {
            lastDragPoint = point
            return
        }
        startPoint = point
        currentPoint = point
    }

    func updateDrawing(to point: CGPoint) {
        if annotationService.selectedTool == .cursor {
            let delta = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
            if let window {
                var frame = window.frame
                frame.origin.x += delta.x
                frame.origin.y -= delta.y
                window.setFrameOrigin(frame.origin)
            }
            lastDragPoint = point
            return
        }

        currentPoint = point
        let rect = createRect(from: startPoint, to: currentPoint)

        switch annotationService.selectedTool {
        case .cursor:
            annotationService.currentDrawingLayer = nil

        case .rectangle:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .rectangle,
                rect: rect,
                color: annotationService.selectedColor,
                lineWidth: annotationService.lineWidth
            )
        case .line:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .line,
                rect: rect,
                color: annotationService.selectedColor,
                lineWidth: annotationService.lineWidth,
                startPoint: startPoint,
                endPoint: currentPoint
            )
        case .ellipse:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .ellipse,
                rect: rect,
                color: annotationService.selectedColor,
                lineWidth: annotationService.lineWidth
            )
        case .arrow:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .arrow,
                rect: rect,
                color: annotationService.selectedColor,
                lineWidth: annotationService.lineWidth,
                startPoint: startPoint,
                endPoint: currentPoint
            )
        case .highlight:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .highlight,
                rect: rect,
                color: annotationService.selectedColor.withAlphaComponent(0.3)
            )
        case .mosaic:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .mosaic,
                rect: rect,
                color: annotationService.selectedColor,
                lineWidth: 0
            )
        }
    }

    func endDrawing() {
        guard isDrawing else { return }
        isDrawing = false

        if annotationService.selectedTool == .cursor {
            return
        }

        let rect = createRect(from: startPoint, to: currentPoint)

        switch annotationService.selectedTool {
        case .cursor:
            break

        case .rectangle:
            annotationService.addRectangle(rect)
        case .ellipse:
            annotationService.addEllipse(rect)
        case .line:
            annotationService.addLine(from: startPoint, to: currentPoint)
        case .arrow:
            annotationService.addArrow(from: startPoint, to: currentPoint)
        case .highlight:
            annotationService.addHighlight(rect)
        case .mosaic:
            annotationService.addMosaic(rect)
        }

        annotationService.currentDrawingLayer = nil
    }

    func undo() {
        annotationService.undo()
    }

    // MARK: - 工具方法

    private func createRect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
    }
}
