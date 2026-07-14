import AppKit

/// 标注工具类型
enum AnnotationTool: String, CaseIterable {
    case cursor
    case rectangle
    case ellipse
    case arrow
    case line
    case text        // 文字标注，替换原来的高亮笔
    case number
    case mosaic

    var displayName: String {
        switch self {
        case .cursor: return "移动"
        case .rectangle: return "框选"
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

/// 标注图层数据
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

/// 截图结果（含选区位置）
struct ScreenshotResult {
    let image: NSImage
    /// 框选区域（屏幕坐标系）
    let selectionRect: CGRect
    let action: ScreenshotSelectionAction

    init(
        image: NSImage,
        selectionRect: CGRect,
        action: ScreenshotSelectionAction = .annotate(.cursor)
    ) {
        self.image = image
        self.selectionRect = selectionRect
        self.action = action
    }
}
