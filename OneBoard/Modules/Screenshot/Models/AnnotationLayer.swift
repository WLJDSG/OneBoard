import AppKit

/// 标注工具类型
enum AnnotationTool: String, CaseIterable {
    case cursor
    case rectangle
    case ellipse
    case arrow
    case line
    case highlight
    case mosaic

    var displayName: String {
        switch self {
        case .cursor: return "移动"
        case .rectangle: return "框选"
        case .ellipse: return "圆形"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .highlight: return "高亮"
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
        case .highlight: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        }
    }
}

/// 标注图层数据
struct AnnotationLayer: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var rect: CGRect
    var color: NSColor
    var text: String?
    var lineWidth: CGFloat
    var startPoint: CGPoint?
    var endPoint: CGPoint?

    init(
        tool: AnnotationTool,
        rect: CGRect,
        color: NSColor = .systemRed,
        text: String? = nil,
        lineWidth: CGFloat = 2.0,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil
    ) {
        self.tool = tool
        self.rect = rect
        self.color = color
        self.text = text
        self.lineWidth = lineWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}
