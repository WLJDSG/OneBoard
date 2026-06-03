import SwiftUI

/// 全屏遮罩 - 使用 AppKit NSView 实现可靠的鼠标拖拽框选
struct ScreenshotOverlayView: View {
    let screenshot: NSImage
    let onConfirm: (NSImage, CGRect) -> Void   // (裁剪图, 屏幕坐标选区)
    let onCancel: () -> Void

    var body: some View {
        ScreenshotOverlayNSView(
            screenshot: screenshot,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
        .ignoresSafeArea()
    }
}

// MARK: - AppKit NSView 实现（可靠的全屏鼠标跟踪）

private struct ScreenshotOverlayNSView: NSViewRepresentable {
    let screenshot: NSImage
    let onConfirm: (NSImage, CGRect) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> OverlayView {
        let view = OverlayView(screenshot: screenshot)
        view.onConfirm = onConfirm
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: OverlayView, context: Context) {}
}

private class OverlayView: NSView {
    let screenshot: NSImage
    var onConfirm: ((NSImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging: Bool = false
    private var localMonitor: Any?

    private var selectionRect: NSRect {
        NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    init(screenshot: NSImage) {
        self.screenshot = screenshot
        super.init(frame: .zero)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frame = window?.contentView?.bounds ?? frame
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // Esc
                self.onCancel?()
                return nil
            }
            if event.keyCode == 36, self.isDragging { // Enter
                self.confirmSelection()
                return nil
            }
            return event
        }
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func removeFromSuperview() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        super.removeFromSuperview()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        if selectionRect.width > 10, selectionRect.height > 10 {
            confirmSelection()
        } else {
            needsDisplay = true
        }
    }

    private func confirmSelection() {
        let rect = selectionRect
        guard rect.width > 10, rect.height > 10 else { return }
        guard let screen = window?.screen ?? NSScreen.main else { return }

        // 屏幕坐标选区（用于窗口定位）
        let screenSelectionRect = CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + (screen.frame.height - rect.maxY),
            width: rect.width,
            height: rect.height
        )

        let scaleX = screenshot.size.width / screen.frame.width
        let scaleY = screenshot.size.height / screen.frame.height
        let cropRect = CGRect(
            x: rect.origin.x * scaleX,
            y: (screen.frame.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral

        guard cropRect.width > 0, cropRect.height > 0,
              let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: cropRect) else { return }

        let result = NSImage(cgImage: cropped, size: cropRect.size)
        onConfirm?(result, screenSelectionRect)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 半透明背景
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.fill(bounds)

        // 选中区域挖空（显示原图）
        if isDragging || (selectionRect.width > 5 && selectionRect.height > 5) {
            let rect = isDragging ? selectionRect : selectionRect

            // 挖空选中区域
            ctx.setBlendMode(.clear)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)

            // 在挖空区域绘制原图
            guard let screen = window?.screen ?? NSScreen.main else { return }
            let scaleX = screenshot.size.width / screen.frame.width
            let scaleY = screenshot.size.height / screen.frame.height
            let srcRect = CGRect(
                x: rect.origin.x * scaleX,
                y: (screen.frame.height - rect.maxY) * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )
            if let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let cropped = cgImage.cropping(to: srcRect.integral) {
                let nsImage = NSImage(cgImage: cropped, size: rect.size)
                nsImage.draw(in: rect)
            }

            // 蓝色边框
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(rect)
        } else {
            // 提示文字
            let text = "拖拽选择截图区域  |  Enter 确认  |  Esc 取消"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let textRect = NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            let bgRect = textRect.insetBy(dx: -16, dy: -10)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(bgPath)
            ctx.fillPath()
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
}
