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
        startPoint = point
        currentPoint = point
    }

    func updateDrawing(to point: CGPoint) {
        currentPoint = point
        let rect = createRect(from: startPoint, to: currentPoint)

        switch annotationService.selectedTool {
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
                lineWidth: annotationService.lineWidth
            )
        case .highlight:
            annotationService.currentDrawingLayer = AnnotationLayer(
                tool: .highlight,
                rect: rect,
                color: annotationService.selectedColor.withAlphaComponent(0.3)
            )
        case .text:
            annotationService.currentDrawingLayer = nil
        }
    }

    func endDrawing() {
        guard isDrawing else { return }
        isDrawing = false

        let rect = createRect(from: startPoint, to: currentPoint)

        switch annotationService.selectedTool {
        case .rectangle:
            annotationService.addRectangle(rect)
        case .line:
            annotationService.addLine(from: startPoint, to: currentPoint)
        case .highlight:
            annotationService.addHighlight(rect)
        case .text:
            isTextInput = true
            annotationService.addText("", at: startPoint)
        }

        annotationService.currentDrawingLayer = nil
    }

    func commitText(_ text: String) {
        guard !text.isEmpty else { return }
        guard !annotationService.layers.isEmpty else { return }
        annotationService.layers[annotationService.layers.count - 1].text = text
        isTextInput = false
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