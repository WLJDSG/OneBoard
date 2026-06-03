import AppKit

/// 标注工具类型
enum AnnotationTool: String, CaseIterable {
    case text
    case line
    case rectangle
    case highlight

    var displayName: String {
        switch self {
        case .text: return "文字"
        case .line: return "直线"
        case .rectangle: return "矩形"
        case .highlight: return "高亮"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "textformat"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .highlight: return "highlighter"
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

    init(
        tool: AnnotationTool,
        rect: CGRect,
        color: NSColor = .systemRed,
        text: String? = nil,
        lineWidth: CGFloat = 2.0
    ) {
        self.tool = tool
        self.rect = rect
        self.color = color
        self.text = text
        self.lineWidth = lineWidth
    }
}