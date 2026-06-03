import AppKit

/// 标注服务 - 管理标注图层状态
@MainActor
final class AnnotationService: ObservableObject {
    @Published var layers: [AnnotationLayer] = []
    @Published var selectedTool: AnnotationTool = .cursor
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 2.0

    /// 当前正在绘制的图层（拖拽中）
    @Published var currentDrawingLayer: AnnotationLayer?

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

    func addEllipse(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .ellipse,
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
            lineWidth: lineWidth,
            startPoint: from,
            endPoint: to
        )
        layers.append(layer)
    }

    func addArrow(from: CGPoint, to: CGPoint) {
        let rect = CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
        let layer = AnnotationLayer(
            tool: .arrow,
            rect: rect,
            color: selectedColor,
            lineWidth: lineWidth,
            startPoint: from,
            endPoint: to
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

    func addMosaic(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .mosaic,
            rect: rect,
            color: .clear,
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
        case .cursor:
            break

        case .rectangle:
            ctx.setStrokeColor(layer.color.cgColor)
            ctx.setLineWidth(layer.lineWidth)
            ctx.stroke(layer.rect)

        case .ellipse:
            ctx.setStrokeColor(layer.color.cgColor)
            ctx.setLineWidth(layer.lineWidth)
            ctx.strokeEllipse(in: layer.rect)

        case .line, .arrow:
            let start = layer.startPoint ?? CGPoint(x: layer.rect.minX, y: layer.rect.minY)
            let end = layer.endPoint ?? CGPoint(x: layer.rect.maxX, y: layer.rect.maxY)
            ctx.setStrokeColor(layer.color.cgColor)
            ctx.setLineWidth(layer.lineWidth)
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            if layer.tool == .arrow {
                drawArrowHead(for: layer, in: ctx)
            }

        case .highlight:
            ctx.setFillColor(layer.color.cgColor)
            ctx.fill(layer.rect)

        case .mosaic:
            drawMosaic(in: layer.rect, context: ctx)

        }

        ctx.restoreGState()
    }

    private func drawArrowHead(for layer: AnnotationLayer, in ctx: CGContext) {
        let start = layer.startPoint ?? CGPoint(x: layer.rect.minX, y: layer.rect.minY)
        let end = layer.endPoint ?? CGPoint(x: layer.rect.maxX, y: layer.rect.maxY)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 12
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let p2 = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.move(to: end)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }

    private func drawMosaic(in rect: CGRect, context ctx: CGContext) {
        let cell: CGFloat = 6
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.68).cgColor)
        ctx.fill(rect)
        for x in stride(from: rect.minX, to: rect.maxX, by: cell) {
            for y in stride(from: rect.minY, to: rect.maxY, by: cell) {
                let seed = sin((x + 17) * 12.9898 + (y + 23) * 78.233) * 43758.5453
                let random = seed - floor(seed)
                let alpha = 0.38 + random * 0.48
                let inset: CGFloat = random > 0.55 ? 0 : 1
                ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
                ctx.fill(CGRect(x: x + inset, y: y + inset, width: cell + 1 - inset, height: cell + 1 - inset))
            }
        }
    }
}
