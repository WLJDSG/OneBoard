import AppKit

/// 标注服务 - 管理标注图层状态
@MainActor
final class AnnotationService: ObservableObject {
    @Published var layers: [AnnotationLayer] = []
    @Published private(set) var redoLayers: [AnnotationLayer] = []
    @Published var selectedTool: AnnotationTool = .cursor
    @Published var selectedColor: NSColor = .systemRed {
        didSet {
            // 颜色切换时立即更新正在绘制的图层，使变化即时可见
            if var layer = currentDrawingLayer, layer.color != selectedColor {
                layer.color = selectedColor
                currentDrawingLayer = layer
            }
        }
    }
    @Published var lineWidth: CGFloat = 2.0
    @Published var numberBadgeSize: CGFloat = 28
    let presetColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemPurple, .systemPink,
        .black, .white
    ]
    @Published var fontSize: CGFloat = 18
    @Published var mosaicBlockSize: CGFloat = 6

    /// 当前正在绘制的图层（拖拽中）
    @Published var currentDrawingLayer: AnnotationLayer?

    private var baseImage: NSImage?

    init(baseImage: NSImage? = nil) {
        self.baseImage = baseImage
    }

    func setBaseImage(_ image: NSImage) {
        self.baseImage = image
    }

    var canUndo: Bool { !layers.isEmpty }
    var canRedo: Bool { !redoLayers.isEmpty }

    private func appendLayer(_ layer: AnnotationLayer) {
        layers.append(layer)
        redoLayers.removeAll()
    }

    // MARK: - 添加标注

    func addRectangle(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .rectangle,
            rect: rect,
            color: selectedColor,
            lineWidth: lineWidth
        )
        appendLayer(layer)
    }

    func addEllipse(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .ellipse,
            rect: rect,
            color: selectedColor,
            lineWidth: lineWidth
        )
        appendLayer(layer)
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
        appendLayer(layer)
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
        appendLayer(layer)
    }

    func addText(at point: CGPoint, text: String, fontSize: CGFloat? = nil) {
        let resolvedFontSize = fontSize ?? self.fontSize
        // 根据文字长度估算初始 rect
        let font = NSFont.systemFont(ofSize: resolvedFontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(
            x: point.x,
            y: point.y,
            width: max(size.width + 16, 60),
            height: max(size.height + 8, 30)
        )
        let layer = AnnotationLayer(
            tool: .text,
            rect: rect,
            color: selectedColor,
            text: text,
            fontSize: resolvedFontSize
        )
        appendLayer(layer)
    }

    func addText(in rect: CGRect, text: String, fontSize: CGFloat? = nil) {
        let resolvedFontSize = fontSize ?? self.fontSize
        let layer = AnnotationLayer(
            tool: .text,
            rect: rect,
            color: selectedColor,
            text: text,
            fontSize: resolvedFontSize
        )
        appendLayer(layer)
    }

    func addMosaic(_ rect: CGRect) {
        let layer = AnnotationLayer(
            tool: .mosaic,
            rect: rect,
            color: .clear,
            lineWidth: mosaicBlockSize
        )
        appendLayer(layer)
    }

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
        appendLayer(layer)
    }

    /// 更新文字标注的位置和大小
    func updateTextLayer(id: UUID, rect: CGRect) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].rect = rect
    }

    /// 更新文字标注的文本
    func updateTextLayer(id: UUID, text: String) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].text = text
    }

    /// 删除指定图层
    func removeLayer(id: UUID) {
        layers.removeAll { $0.id == id }
        redoLayers.removeAll()
    }

    // MARK: - 操作

    func undo() {
        guard let layer = layers.popLast() else { return }
        redoLayers.append(layer)
    }

    func redo() {
        guard let layer = redoLayers.popLast() else { return }
        layers.append(layer)
    }

    func removeAll() {
        layers.removeAll()
        redoLayers.removeAll()
    }

    // MARK: - 样式控制

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
            lineWidth = lineWidth >= 12 ? 1 : lineWidth + 1
        case .text:
            fontSize = fontSize >= 48 ? 12 : fontSize + 2
        case .number:
            numberBadgeSize = numberBadgeSize >= 48 ? 20 : numberBadgeSize + 2
        case .mosaic:
            mosaicBlockSize = mosaicBlockSize >= 24 ? 4 : mosaicBlockSize + 2
        }
    }

    func decrementStyleValue() {
        switch selectedTool {
        case .cursor:
            break
        case .rectangle, .ellipse, .arrow, .line:
            lineWidth = lineWidth <= 1 ? 12 : lineWidth - 1
        case .text:
            fontSize = fontSize <= 12 ? 48 : fontSize - 2
        case .number:
            numberBadgeSize = numberBadgeSize <= 20 ? 48 : numberBadgeSize - 2
        case .mosaic:
            mosaicBlockSize = mosaicBlockSize <= 4 ? 24 : mosaicBlockSize - 2
        }
    }

    // MARK: - 渲染

    /// 将所有标注渲染到图片上
    func renderToImage(baseImage: NSImage, displaySize: CGSize? = nil) -> NSImage {
        let outputPointSize = displaySize ?? baseImage.size
        let pixelSize = Self.pixelSize(for: baseImage)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
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
        rep.size = outputPointSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        // 绘制原图
        baseImage.draw(in: CGRect(origin: .zero, size: pixelSize),
                       from: CGRect(origin: .zero, size: baseImage.size),
                       operation: .copy,
                       fraction: 1.0)

        // 绘制标注图层
        let ctx = context.cgContext
        let scaleX = pixelSize.width / max(outputPointSize.width, 1)
        let scaleY = pixelSize.height / max(outputPointSize.height, 1)

        // 第一遍：绘制形状标注（矩形/椭圆/直线/箭头/马赛克），通过 CTM 做坐标系变换
        ctx.saveGState()
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: 0, y: outputPointSize.height)
        ctx.scaleBy(x: 1, y: -1)
        for layer in layers {
            drawShapeLayer(layer, in: ctx)
        }
        ctx.restoreGState()

        // 第二遍：绘制文字和编号标注，直接用像素坐标，避免 CTM 双重翻转导致的漂移
        for layer in layers {
            drawTextOrNumberLayer(layer, scaleX: scaleX, scaleY: scaleY,
                                  displayHeight: outputPointSize.height,
                                  pixelHeight: pixelSize.height)
        }

        NSGraphicsContext.restoreGraphicsState()

        let renderedImage = NSImage(size: outputPointSize)
        renderedImage.addRepresentation(rep)
        return renderedImage
    }

    static func pixelSize(for image: NSImage) -> CGSize {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }


    static func pixelSizeDescription(for image: NSImage) -> String {
        let size = pixelSize(for: image)
        return "\(Int(size.width)) x \(Int(size.height))"
    }

    private func drawShapeLayer(_ layer: AnnotationLayer, in ctx: CGContext) {
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

        case .text, .number:
            break  // 文字/编号在第二遍渲染中通过 drawTextOrNumberLayer 单独处理

        case .mosaic:
            drawMosaic(in: layer.rect, blockSize: layer.lineWidth, context: ctx)

        }

        ctx.restoreGState()
    }

    private func drawText(_ text: String, rect: CGRect, color: NSColor, fontSize: CGFloat, in ctx: CGContext, canvasHeight: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let nsText = text as NSString
        // 在 rect 内居中绘制
        let textSize = nsText.size(withAttributes: attrs)
        let drawRect = CGRect(
            x: rect.minX + 4,
            y: rect.midY - textSize.height / 2,
            width: rect.width - 8,
            height: textSize.height
        )
        let appKitRect = CGRect(
            x: drawRect.minX,
            y: canvasHeight - drawRect.maxY,
            width: drawRect.width,
            height: drawRect.height
        )

        ctx.saveGState()
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -canvasHeight)
        nsText.draw(in: appKitRect, withAttributes: attrs)
        ctx.restoreGState()
    }

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

    private func drawMosaic(in rect: CGRect, blockSize: CGFloat, context ctx: CGContext) {
        let cell = max(4, blockSize)
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

    // MARK: - 直接像素坐标文字/编号渲染（避免 CTM 双重翻转）

    /// 将 display 坐标 (Y=0 在顶部) 转换为 CGContext 像素坐标 (Y=0 在底部)
    private func toPixelRect(_ displayRect: CGRect, scaleX: CGFloat, scaleY: CGFloat, pixelHeight: CGFloat) -> CGRect {
        CGRect(
            x: displayRect.minX * scaleX,
            y: pixelHeight - (displayRect.minY + displayRect.height) * scaleY,
            width: displayRect.width * scaleX,
            height: displayRect.height * scaleY
        )
    }

    private func drawTextOrNumberLayer(_ layer: AnnotationLayer, scaleX: CGFloat, scaleY: CGFloat,
                                        displayHeight: CGFloat, pixelHeight: CGFloat) {
        switch layer.tool {
        case .text:
            guard let text = layer.text else { return }
            let pixelFontSize = layer.fontSize * scaleY
            let font = NSFont.systemFont(ofSize: pixelFontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: layer.color
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let pixelRect = toPixelRect(layer.rect, scaleX: scaleX, scaleY: scaleY, pixelHeight: pixelHeight)
            let drawRect = CGRect(
                x: pixelRect.minX + 4 * scaleX,
                y: pixelRect.minY,
                width: max(pixelRect.width - 8 * scaleX, textSize.width),
                height: textSize.height
            )
            (text as NSString).draw(in: drawRect, withAttributes: attrs)

        case .number:
            guard let number = layer.numberValue else { return }
            let pixelRadius = (layer.rect.width / 2) * scaleX
            let centerX = layer.rect.midX * scaleX
            let centerY = pixelHeight - layer.rect.midY * scaleY

            // 绘制圆形背景
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.setFillColor(layer.color.cgColor)
            ctx.fillEllipse(in: CGRect(x: centerX - pixelRadius, y: centerY - pixelRadius,
                                        width: pixelRadius * 2, height: pixelRadius * 2))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(max(1, layer.lineWidth * scaleX))
            ctx.strokeEllipse(in: CGRect(x: centerX - pixelRadius + 1, y: centerY - pixelRadius + 1,
                                          width: pixelRadius * 2 - 2, height: pixelRadius * 2 - 2))
            ctx.restoreGState()

            // 绘制编号文字
            let textColor = contrastingTextColor(for: layer.color)
            let pixelFontSize = layer.fontSize * scaleY
            let font = NSFont.systemFont(ofSize: pixelFontSize, weight: .bold)
            let text = "\(number)" as NSString
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let numSize = text.size(withAttributes: numAttrs)
            let numRect = CGRect(
                x: centerX - numSize.width / 2,
                y: centerY - numSize.height / 2,
                width: numSize.width,
                height: numSize.height
            )
            text.draw(in: numRect, withAttributes: numAttrs)

        default:
            break
        }
    }
}
