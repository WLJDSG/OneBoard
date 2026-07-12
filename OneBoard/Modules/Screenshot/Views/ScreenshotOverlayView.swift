import SwiftUI

// MARK: - 事件管理器（负责 monitor / timer 生命周期）

/// 持有 NSEvent monitor 和 Timer，由 ScreenshotCaptureService 负责清理
final class OverlayEventManager {
    var keyMonitor: Any?
    var mouseMonitor: Any?
    var windowQueryTimer: Timer?

    func cleanup() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        windowQueryTimer?.invalidate()
        windowQueryTimer = nil
    }

    deinit { cleanup() }
}

// MARK: - 裁剪坐标映射

enum ScreenshotCropMapper {
    static func cropRect(forOverlayRect rect: CGRect,
                         screenFrame: CGRect,
                         imagePixelSize: CGSize) -> CGRect {
        guard screenFrame.width > 0, screenFrame.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return .zero
        }

        let sx = imagePixelSize.width / screenFrame.width
        let sy = imagePixelSize.height / screenFrame.height
        let pixelRect = CGRect(
            x: rect.minX * sx,
            y: (screenFrame.height - rect.maxY) * sy,
            width: rect.width * sx,
            height: rect.height * sy
        ).integral

        return pixelRect.intersection(CGRect(origin: .zero, size: imagePixelSize))
    }

    static func screenRect(forOverlayRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.minY + (screenFrame.height - rect.maxY),
            width: rect.width,
            height: rect.height
        )
    }
}

// MARK: - 全屏遮罩视图

/// 全屏遮罩 - 使用 AppKit NSView 处理鼠标拖拽，避免 SwiftUI 手势在关窗时重复回调。
struct ScreenshotOverlayView: View {
    let screenshot: NSImage
    let onConfirm: (NSImage, CGRect) -> Void
    let onCancel: () -> Void
    let eventManager: OverlayEventManager

    var body: some View {
        ScreenshotOverlayNSView(
            screenshot: screenshot,
            onConfirm: onConfirm,
            onCancel: onCancel,
            eventManager: eventManager
        )
        .ignoresSafeArea()
    }
}

// MARK: - AppKit NSView 实现（稳定的全屏鼠标跟踪）

private struct ScreenshotOverlayNSView: NSViewRepresentable {
    let screenshot: NSImage
    let onConfirm: (NSImage, CGRect) -> Void
    let onCancel: () -> Void
    let eventManager: OverlayEventManager

    func makeNSView(context: Context) -> OverlayView {
        let view = OverlayView(screenshot: screenshot, eventManager: eventManager)
        view.onConfirm = onConfirm
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: OverlayView, context: Context) {}
}

final class ScreenshotOverlayContentView: NSView {
    let screenshot: NSImage
    let eventManager: OverlayEventManager
    var onConfirm: ((NSImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let cachedCGImage: CGImage?
    private let imagePixelSize: CGSize
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var hasFinished = false

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    init(screenshot: NSImage, eventManager: OverlayEventManager) {
        self.screenshot = screenshot
        self.eventManager = eventManager
        // 安全获取 CGImage：NSImage.cgImage 在部分显示器配置下可能崩溃
        if let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.cachedCGImage = cg
            self.imagePixelSize = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        } else if let tiff = screenshot.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let cg = bitmap.cgImage {
            self.cachedCGImage = cg
            self.imagePixelSize = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        } else {
            self.cachedCGImage = nil
            self.imagePixelSize = screenshot.size
        }
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frame = window?.contentView?.bounds ?? frame
        window?.makeFirstResponder(self)

        eventManager.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53:
                self.finishCancel()
                return nil
            case 36:
                self.confirmCurrentSelection()
                return nil
            default:
                return event
            }
        }
    }

    override func removeFromSuperview() {
        eventManager.cleanup()
        super.removeFromSuperview()
    }

    override func mouseDown(with event: NSEvent) {
        guard !hasFinished else { return }
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasFinished, startPoint != nil else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !hasFinished, startPoint != nil else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        confirmCurrentSelection()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 先覆盖全屏暗色遮罩，框选时再挖空选区露出底下的屏幕内容。
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)

        if let rect = selectionRect, rect.width > 1, rect.height > 1 {
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.fill(rect)
            ctx.restoreGState()

            OneBoardColors.nsAccent.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()

            drawSizeLabel(for: rect)
        } else {
            drawHint()
        }
    }

    private func confirmCurrentSelection() {
        guard !hasFinished,
              let rect = selectionRect,
              rect.width > 10,
              rect.height > 10,
              let screen = window?.screen ?? NSScreen.main,
              let cg = cachedCGImage else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        let crop = ScreenshotCropMapper.cropRect(
            forOverlayRect: rect,
            screenFrame: screen.frame,
            imagePixelSize: imagePixelSize
        )
        guard crop.width > 10,
              crop.height > 10,
              let cropped = cg.cropping(to: crop) else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        hasFinished = true
        guard let confirm = onConfirm else {
            print("[ScreenshotOverlay] onConfirm 未设置，无法完成截图")
            return
        }
        // CGImage 保留 Retina 原始像素，NSImage 的逻辑尺寸使用框选的屏幕点尺寸。
        let result = NSImage(cgImage: cropped, size: rect.size)
        confirm(result, ScreenshotCropMapper.screenRect(forOverlayRect: rect, screenFrame: screen.frame))
    }

    private func finishCancel() {
        guard !hasFinished else { return }
        hasFinished = true
        onCancel?()
    }

    private func drawHint() {
        let title = "拖拽选择截图区域"
        let subtitle = "Enter 确认  ·  Esc 取消"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]

        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
        let contentWidth = max(titleSize.width, subtitleSize.width)
        let contentHeight = titleSize.height + 8 + subtitleSize.height
        let bgRect = NSRect(
            x: bounds.midX - contentWidth / 2 - 20,
            y: bounds.midY - contentHeight / 2 - 12,
            width: contentWidth + 40,
            height: contentHeight + 24
        )

        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8).fill()

        (title as NSString).draw(
            at: NSPoint(x: bounds.midX - titleSize.width / 2, y: bgRect.midY + 4),
            withAttributes: titleAttributes
        )
        (subtitle as NSString).draw(
            at: NSPoint(x: bounds.midX - subtitleSize.width / 2, y: bgRect.midY - subtitleSize.height - 4),
            withAttributes: subtitleAttributes
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let labelRect = NSRect(
            x: min(max(rect.maxX - textSize.width - 12, bounds.minX + 4), bounds.maxX - textSize.width - 12),
            y: min(rect.maxY + 8, bounds.maxY - textSize.height - 8),
            width: textSize.width + 12,
            height: textSize.height + 6
        )

        OneBoardColors.nsAccent.setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(
            at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 3),
            withAttributes: attributes
        )
    }
}

private typealias OverlayView = ScreenshotOverlayContentView
