import AppKit

/// 标注服务 - 管理标注图层状态
@MainActor
final class AnnotationService: ObservableObject {
    @Published var layers: [AnnotationLayer] = []
    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 2.0

    /// 当前正在绘制的图层（拖拽中）
    @Published var currentDrawingLayer: AnnotationLayer?

    /// 当前正在输入的文字
    @Published var currentTextInput: String = ""

    private var baseImage: NSImage?

    init(baseImage: NSImage? = nil) {
        self.baseImage = baseImage
    }

    func setBaseImage(_ image: NSImage) {
        self.baseImage = image
    }

    // MARK: - 添加标注

    func addRectangle(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .rectangle,
            rect: rect,
            color: selectedColor,
            lineWidth: lineWidth
        )
        layers.append(layer)
    }

    func addLine(from: CGPoint, to: CGPoint) {
        let rect = CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
        let layer = AnnotationLayer(
            tool: .line,
            rect: rect,
            color: selectedColor,
            lineWidth: lineWidth
        )
        layers.append(layer)
    }

    func addHighlight(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .highlight,
            rect: rect,
            color: selectedColor.withAlphaComponent(0.3),
            lineWidth: 0
        )
        layers.append(layer)
    }

    func addText(_ text: String, at point: CGPoint) {
        let estimatedSize = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 18)
        ])
        let rect = CGRect(
            x: point.x,
            y: point.y - estimatedSize.height,
            width: max(estimatedSize.width + 20, 100),
            height: estimatedSize.height + 10
        )
        let layer = AnnotationLayer(
            tool: .text,
            rect: rect,
            color: selectedColor,
            text: text,
            lineWidth: 0
        )
        layers.append(layer)
    }

    // MARK: - 操作

    func undo() {
        guard !layers.isEmpty else { return }
        layers.removeLast()
    }

    func removeAll() {
        layers.removeAll()
    }

    // MARK: - 渲染

    /// 将所有标注渲染到图片上
    func renderToImage(baseImage: NSImage) -> NSImage {
        let size = baseImage.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return baseImage
        }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return baseImage
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // 绘制原图
        baseImage.draw(in: CGRect(origin: .zero, size: size),
                       from: .zero, operation: .copy, fraction: 1.0)

        // 绘制标注图层
        for layer in layers {
            drawLayer(layer, in: context.cgContext)
        }

        NSGraphicsContext.restoreGraphicsState()

        let renderedImage = NSImage(size: size)
        renderedImage.addRepresentation(rep)
        return renderedImage
    }

    private func drawLayer(_ layer: AnnotationLayer, in ctx: CGContext) {
        ctx.saveGState()

        switch layer.tool {
        case .rectangle:
            ctx.setStrokeColor(layer.color.cgColor)
            ctx.setLineWidth(layer.lineWidth)
            ctx.stroke(layer.rect)

        case .line:
            ctx.setStrokeColor(layer.color.cgColor)
            ctx.setLineWidth(layer.lineWidth)
            ctx.move(to: CGPoint(x: layer.rect.minX, y: layer.rect.minY))
            ctx.addLine(to: CGPoint(x: layer.rect.maxX, y: layer.rect.maxY))
            ctx.strokePath()

        case .highlight:
            ctx.setFillColor(layer.color.cgColor)
            ctx.fill(layer.rect)

        case .text:
            if let text = layer.text {
                let nsColor = layer.color
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: nsColor,
                    .backgroundColor: NSColor.white.withAlphaComponent(0.7)
                ]
                (text as NSString).draw(in: layer.rect, withAttributes: attributes)
            }
        }

        ctx.restoreGState()
    }
}