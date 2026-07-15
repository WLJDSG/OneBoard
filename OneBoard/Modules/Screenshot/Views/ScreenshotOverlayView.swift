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
            y: screenFrame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
    }
}

// MARK: - 全屏遮罩视图

/// 全屏遮罩 - 使用 AppKit NSView 处理鼠标拖拽，避免 SwiftUI 手势在关窗时重复回调。
struct ScreenshotOverlayView: View {
    let screenshot: NSImage
    let onConfirm: (NSImage, CGRect, ScreenshotSelectionAction) -> Void
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
    let onConfirm: (NSImage, CGRect, ScreenshotSelectionAction) -> Void
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
    var onConfirm: ((NSImage, CGRect, ScreenshotSelectionAction) -> Void)?
    var onCancel: (() -> Void)?

    private let cachedCGImage: CGImage?
    private let imagePixelSize: CGSize
    private var selectionModel = ScreenshotSelectionModel()
    private var selectionToolbarView: NSHostingView<ScreenshotSelectionToolbarView>?
    private var hasFinished = false
    private var annotationService: AnnotationService?
    private var annotationViewModel: AnnotationViewModel?
    private var annotationCanvasView: NSView?
    private var annotationToolbarView: NSView?

    private var selectionRect: NSRect? {
        selectionModel.rect
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
            guard self.annotationService == nil else { return event }
            switch event.keyCode {
            case 53:
                self.finishCancel()
                return nil
            case 36:
                self.beginInlineAnnotation()
                return nil
            default:
                return event
            }
        }
    }

    override func removeFromSuperview() {
        selectionToolbarView?.removeFromSuperview()
        selectionToolbarView = nil
        annotationCanvasView?.removeFromSuperview()
        annotationToolbarView?.removeFromSuperview()
        eventManager.cleanup()
        super.removeFromSuperview()
    }

    override func mouseDown(with event: NSEvent) {
        guard !hasFinished, annotationService == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, selectionRect?.contains(point) == true {
            beginInlineAnnotation()
            return
        }
        hideSelectionToolbar()
        selectionModel.begin(at: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasFinished, annotationService == nil else { return }
        selectionModel.update(to: convert(event.locationInWindow, from: nil), bounds: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !hasFinished, annotationService == nil else { return }
        selectionModel.end(at: convert(event.locationInWindow, from: nil), bounds: bounds)
        showSelectionToolbarIfNeeded()
        needsDisplay = true
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

            if annotationService == nil {
                drawResizeHandles(for: rect)
                drawSizeLabel(for: rect)
            }
        } else {
            drawHint()
        }
    }

    private func beginInlineAnnotation(_ tool: AnnotationTool = .cursor) {
        guard !hasFinished, annotationService == nil,
              let rect = selectionModel.lock(),
              rect.width > 10,
              rect.height > 10,
              let window,
              let screen = window.screen ?? NSScreen.main,
              let cg = cachedCGImage else {
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
            selectionModel.unlockAfterFailedCrop()
            needsDisplay = true
            return
        }

        let image = NSImage(cgImage: cropped, size: rect.size)
        let service = AnnotationService(baseImage: image)
        service.selectedColor = .systemRed
        service.selectedTool = tool
        let viewModel = AnnotationViewModel(annotationService: service)

        let canvas = NSHostingView(
            rootView: AnnotationCanvasView(
                baseImage: image,
                displaySize: rect.size,
                annotationService: service,
                viewModel: viewModel,
                onCopy: { [weak self] image in self?.finishAnnotation(image, action: .copy) },
                onSave: { [weak self] image in self?.finishAnnotation(image, action: .save) },
                onPin: { [weak self] image in self?.finishAnnotation(image, action: .pin) },
                onOCR: { [weak self] image in self?.finishAnnotation(image, action: .ocr) },
                onTranslate: { [weak self] image in self?.finishAnnotation(image, action: .translate) },
                onClose: { [weak self] in self?.finishCancel() }
            )
        )
        canvas.frame = rect
        addSubview(canvas)

        let toolbar = NSHostingView(
            rootView: AnnotationToolbarView(
                annotationService: service,
                viewModel: viewModel,
                onComplete: { [weak self] image in self?.finishAnnotation(image, action: .copy) },
                onSave: { [weak self] image in self?.finishAnnotation(image, action: .save) },
                onPin: { [weak self] image in self?.finishAnnotation(image, action: .pin) },
                onOCR: { [weak self] image in self?.finishAnnotation(image, action: .ocr) },
                onTranslate: { [weak self] image in self?.finishAnnotation(image, action: .translate) },
                onClose: { [weak self] in self?.finishCancel() },
                baseImage: image,
                displaySize: rect.size
            )
        )
        let toolbarSize = toolbar.fittingSize
        toolbar.frame = inlineToolbarFrame(selectionRect: rect, toolbarSize: toolbarSize)
        addSubview(toolbar, positioned: .above, relativeTo: canvas)

        annotationService = service
        annotationViewModel = viewModel
        annotationCanvasView = canvas
        annotationToolbarView = toolbar
        viewModel.setWindow(window, coordinateView: canvas, allowsWindowDragging: false)
        needsDisplay = true
    }

    private func finishAnnotation(_ image: NSImage, action: ScreenshotSelectionAction) {
        guard !hasFinished, let rect = selectionRect,
              let screen = window?.screen ?? NSScreen.main else { return }
        hasFinished = true
        onConfirm?(
            image,
            ScreenshotCropMapper.screenRect(forOverlayRect: rect, screenFrame: screen.frame),
            action
        )
    }

    private func finishSelection(_ action: ScreenshotSelectionAction) {
        guard !hasFinished,
              let rect = selectionModel.lock(),
              rect.width > 10,
              rect.height > 10,
              let screen = window?.screen ?? NSScreen.main,
              let cg = cachedCGImage else {
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
            selectionModel.unlockAfterFailedCrop()
            showSelectionToolbarIfNeeded()
            needsDisplay = true
            return
        }

        hasFinished = true
        let image = NSImage(cgImage: cropped, size: rect.size)
        onConfirm?(
            image,
            ScreenshotCropMapper.screenRect(forOverlayRect: rect, screenFrame: screen.frame),
            action
        )
    }

    private func showSelectionToolbarIfNeeded() {
        guard selectionModel.phase == .adjusting, let rect = selectionRect else {
            hideSelectionToolbar()
            return
        }

        let hostingView: NSHostingView<ScreenshotSelectionToolbarView>
        if let existing = selectionToolbarView {
            hostingView = existing
        } else {
            hostingView = NSHostingView(
                rootView: ScreenshotSelectionToolbarView { [weak self] action in
                    switch action {
                    case .annotate(let tool):
                        self?.hideSelectionToolbar()
                        self?.beginInlineAnnotation(tool)
                    default:
                        self?.finishSelection(action)
                    }
                }
            )
            hostingView.wantsLayer = true
            addSubview(hostingView)
            selectionToolbarView = hostingView
        }

        let fittingSize = hostingView.fittingSize
        hostingView.frame = ScreenshotSelectionToolbarLayout.frame(
            selectionRect: rect,
            toolbarSize: fittingSize,
            bounds: bounds,
            gap: 12
        )
        hostingView.isHidden = false
    }

    private func hideSelectionToolbar() {
        selectionToolbarView?.isHidden = true
    }

    private func inlineToolbarFrame(selectionRect: CGRect, toolbarSize: CGSize) -> CGRect {
        let horizontalInset: CGFloat = 12
        let gap: CGFloat = 12
        let width = min(toolbarSize.width, bounds.width - horizontalInset * 2)
        let height = toolbarSize.height
        let belowY = selectionRect.minY - gap - height
        let y = belowY >= bounds.minY + horizontalInset
            ? belowY
            : min(selectionRect.maxY + gap, bounds.maxY - height - horizontalInset)
        let x = min(
            max(selectionRect.midX - width / 2, bounds.minX + horizontalInset),
            bounds.maxX - width - horizontalInset
        )
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func drawResizeHandles(for rect: CGRect) {
        for handle in ScreenshotResizeHandle.allCases {
            let center = handle.center(in: rect)
            let handleRect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            OneBoardColors.nsAccent.setStroke()
            let path = NSBezierPath(ovalIn: handleRect)
            path.lineWidth = 1.5
            path.fill()
            path.stroke()
        }
    }

    private func finishCancel() {
        guard !hasFinished else { return }
        hasFinished = true
        onCancel?()
    }

    private func drawHint() {
        let title = "拖拽选择截图区域"
        let subtitle = "松开后可移动和缩放  ·  Esc 取消"
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
