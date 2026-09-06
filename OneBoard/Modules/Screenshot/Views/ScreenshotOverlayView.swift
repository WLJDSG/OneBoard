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

private final class ScreenshotToolbarHostingView: NSHostingView<AnnotationToolbarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ScreenshotOverlayContentView: NSView {
    let screenshot: NSImage
    let eventManager: OverlayEventManager
    var onConfirm: ((NSImage, CGRect, ScreenshotSelectionAction) -> Void)?
    var onCancel: (() -> Void)?

    private let cachedCGImage: CGImage?
    private let imagePixelSize: CGSize
    private var selectionModel = ScreenshotSelectionModel()
    private let windowCandidates: [CGRect]
    private var hoveredWindowRect: CGRect?
    private var windowClickAnchor: CGPoint?
    private var pendingWindowRect: CGRect?
    private var hoverTrackingArea: NSTrackingArea?

    private var selectionToolbarView: NSHostingView<AnnotationToolbarView>?
    private var longCaptureButton: NSButton?
    private var isToolbarMouseInteraction = false
    private var hasFinished = false
    private var isAnnotationLocked = false
    private var annotationService: AnnotationService?
    private var annotationViewModel: AnnotationViewModel?
    private var annotationCanvasView: NSView?

    private var selectionRect: NSRect? {
        selectionModel.rect
    }

    var annotationServiceForTesting: AnnotationService? { annotationService }
    var hasAnnotationCanvasForTesting: Bool { annotationCanvasView != nil }
    var canCropSelectionForTesting: Bool {
        selectionRect.flatMap { croppedImage(for: $0) } != nil
    }

    init(screenshot: NSImage, eventManager: OverlayEventManager, windowCandidates: [CGRect] = []) {
        self.windowCandidates = windowCandidates
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

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frame = window?.contentView?.bounds ?? frame
        window?.makeFirstResponder(self)
        if let window { updateWindowHover(at: convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)) }

        eventManager.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            guard !self.isAnnotationLocked else { return event }
            switch event.keyCode {
            case 53:
                self.finishCancel()
                return nil
            case 36:
                self.finishSelection(.copy)
                return nil
            default:
                return event
            }
        }
    }

    override func removeFromSuperview() {
        selectionToolbarView?.removeFromSuperview()
        selectionToolbarView = nil
        longCaptureButton?.removeFromSuperview()
        longCaptureButton = nil
        annotationCanvasView?.removeFromSuperview()
        eventManager.cleanup()
        super.removeFromSuperview()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateWindowHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateWindowHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredWindowRect = nil
        needsDisplay = true
    }

    private func updateWindowHover(at point: CGPoint) {
        guard !hasFinished, !isAnnotationLocked, selectionModel.rect == nil, windowClickAnchor == nil else { return }
        hoveredWindowRect = windowCandidates.first { $0.contains(point) }
        needsDisplay = true
    }

    func refreshPointerHover() {
        guard let window else { return }
        updateWindowHover(at: convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard !hasFinished, !isAnnotationLocked else { return }
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        // SwiftUI 未消费的工具栏事件也不能交给框选状态机。
        isToolbarMouseInteraction = selectionToolbarView.map { !$0.isHidden && $0.frame.contains(point) } ?? false
        guard !isToolbarMouseInteraction else { return }
        if shouldBeginAnnotation(at: point) {
            beginInlineAnnotation(firstEvent: event)
            return
        }
        if selectionModel.rect == nil, let candidate = windowCandidates.first(where: { $0.contains(point) }) {
            // 按下时仍是窗口预选；超过阈值才从原始按下位置开始自定义框选。
            pendingWindowRect = candidate
            windowClickAnchor = point
            hoveredWindowRect = candidate
            needsDisplay = true
            return
        }
        hoveredWindowRect = nil
        hideSelectionToolbar()
        selectionModel.begin(at: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasFinished, !isAnnotationLocked, !isToolbarMouseInteraction else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let anchor = windowClickAnchor {
            guard hypot(point.x - anchor.x, point.y - anchor.y) > 4 else { return }
            pendingWindowRect = nil
            windowClickAnchor = nil
            hoveredWindowRect = nil
            selectionModel.begin(at: anchor, bounds: bounds)
        }
        selectionModel.update(to: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isToolbarMouseInteraction {
            isToolbarMouseInteraction = false
            return
        }
        guard !hasFinished, !isAnnotationLocked else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let anchor = windowClickAnchor, let rect = pendingWindowRect {
            if hypot(point.x - anchor.x, point.y - anchor.y) <= 4 {
                selectionModel = ScreenshotSelectionModel(rect: rect)
            } else {
                selectionModel.begin(at: anchor, bounds: bounds)
                selectionModel.end(at: point, bounds: bounds)
            }
        } else {
            selectionModel.end(at: point, bounds: bounds)
        }
        windowClickAnchor = nil
        pendingWindowRect = nil
        hoveredWindowRect = nil
        showSelectionToolbarIfNeeded()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 预览与输出使用同一张每屏截图。透明挖洞会让 WindowServer 将鼠标交给底层窗口。
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)
        if let cachedCGImage {
            ctx.interpolationQuality = .none
            ctx.draw(cachedCGImage, in: bounds)
        }
        let previewRect = selectionRect ?? hoveredWindowRect
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.beginPath()
        ctx.addRect(bounds)
        if let rect = previewRect, rect.width > 1, rect.height > 1 {
            ctx.addRect(rect)
        }
        ctx.drawPath(using: .eoFill)

        if let rect = previewRect, rect.width > 1, rect.height > 1 {

            OneBoardColors.nsAccent.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()

            if !isAnnotationLocked {
                if selectionRect != nil { drawResizeHandles(for: rect) }
                drawSizeLabel(for: rect)
            }
        } else {
            drawHint()
        }
    }

    private func shouldBeginAnnotation(at point: CGPoint) -> Bool {
        guard let rect = selectionRect,
              rect.contains(point),
              selectionModel.handle(at: point, hitRadius: ScreenshotSelectionModel.handleHitRadius) == nil,
              let tool = annotationService?.selectedTool else {
            return false
        }
        return tool != .cursor
    }

    private func beginInlineAnnotation(firstEvent: NSEvent? = nil) {
        guard !hasFinished, !isAnnotationLocked,
              let rect = selectionModel.lock(),
              rect.width > 10,
              rect.height > 10,
              let window,
              let image = croppedImage(for: rect),
              let service = annotationService,
              let viewModel = annotationViewModel else {
            return
        }
        isAnnotationLocked = true
        service.setBaseImage(image)

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

        updateToolbar(service: service, viewModel: viewModel, image: image, selectionRect: rect)
        if let toolbar = selectionToolbarView {
            addSubview(toolbar, positioned: .above, relativeTo: canvas)
        }
        annotationCanvasView = canvas
        viewModel.setWindow(window, coordinateView: canvas, allowsWindowDragging: false)
        if let firstEvent {
            let localPoint = canvas.convert(firstEvent.locationInWindow, from: nil)
            let imagePoint = AnnotationCoordinateMapper.imagePoint(
                from: localPoint,
                boundsHeight: canvas.bounds.height,
                isFlipped: canvas.isFlipped
            )
            viewModel.beginInteraction(at: imagePoint, event: firstEvent)
        }
        needsDisplay = true
    }

    private func finishAnnotation(_ image: NSImage, action: ScreenshotSelectionAction) {
        guard !hasFinished, let rect = selectionRect else { return }
        let screenFrame = window?.screen?.frame ?? window?.frame ?? CGRect(origin: .zero, size: bounds.size)
        hasFinished = true
        onConfirm?(
            image,
            ScreenshotCropMapper.screenRect(forOverlayRect: rect, screenFrame: screenFrame),
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
        guard let image = croppedImage(for: rect) else {
            hideSelectionToolbar()
            return
        }

        let service: AnnotationService
        let viewModel: AnnotationViewModel
        if let existingService = annotationService, let existingViewModel = annotationViewModel {
            service = existingService
            viewModel = existingViewModel
            service.setBaseImage(image)
        } else {
            service = AnnotationService(baseImage: image)
            service.selectedColor = .systemRed
            viewModel = AnnotationViewModel(annotationService: service)
            annotationService = service
            annotationViewModel = viewModel
        }
        updateToolbar(service: service, viewModel: viewModel, image: image, selectionRect: rect)
    }

    private func updateToolbar(
        service: AnnotationService,
        viewModel: AnnotationViewModel,
        image: NSImage,
        selectionRect: CGRect
    ) {
        let rootView = AnnotationToolbarView(
            annotationService: service,
            viewModel: viewModel,
            onToolSelected: { [weak self] tool in
                self?.handleAnnotationToolSelection(tool)
            },
            onComplete: { [weak self] image in self?.finishToolbarOutput(image, action: .copy) },
            onSave: { [weak self] image in self?.finishToolbarOutput(image, action: .save) },
            onPin: { [weak self] image in self?.finishToolbarOutput(image, action: .pin) },
            onOCR: { [weak self] image in self?.finishToolbarOutput(image, action: .ocr) },
            onTranslate: { [weak self] image in self?.finishToolbarOutput(image, action: .translate) },
            onLongCapture: { [weak self] in self?.finishSelection(.longCapture) },
            onClose: { [weak self] in self?.finishCancel() },
            baseImage: image,
            displaySize: selectionRect.size
        )

        let hostingView: NSHostingView<AnnotationToolbarView>
        if let existing = selectionToolbarView {
            existing.rootView = rootView
            hostingView = existing
        } else {
            hostingView = ScreenshotToolbarHostingView(rootView: rootView)
            hostingView.wantsLayer = true
            addSubview(hostingView)
            selectionToolbarView = hostingView
        }
        let fittingSize = hostingView.fittingSize
        hostingView.frame = inlineToolbarFrame(selectionRect: selectionRect, toolbarSize: fittingSize)
        hostingView.isHidden = false
        longCaptureButton?.isHidden = true
    }

    private func installLongCaptureButton(nextTo toolbar: NSView) {
        let button = longCaptureButton ?? NSButton(title: "长截图", target: self, action: #selector(beginLongCapture))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "长截图")
        button.imagePosition = .imageLeading
        button.sizeToFit()
        let width = max(button.frame.width + 12, 82)
        var x = toolbar.frame.maxX + 8
        if x + width > bounds.maxX - 12 { x = toolbar.frame.minX - width - 8 }
        button.frame = CGRect(x: x, y: toolbar.frame.minY + 4, width: width, height: max(28, toolbar.frame.height - 8))
        if button.superview == nil { addSubview(button) }
        button.isHidden = false
        longCaptureButton = button
    }

    @objc private func beginLongCapture() {
        finishSelection(.longCapture)
    }

    func handleAnnotationToolSelection(_ tool: AnnotationTool) {
        annotationService?.selectedTool = tool
        guard tool != .cursor, !isAnnotationLocked else { return }
        beginInlineAnnotation()
    }

    private func finishToolbarOutput(_ image: NSImage, action: ScreenshotSelectionAction) {
        guard !hasFinished else { return }
        if !isAnnotationLocked {
            guard selectionModel.lock() != nil else { return }
        }
        finishAnnotation(image, action: action)
    }

    private func croppedImage(for rect: CGRect) -> NSImage? {
        guard let cg = cachedCGImage else { return nil }
        let crop = ScreenshotCropMapper.cropRect(
            forOverlayRect: rect,
            screenFrame: CGRect(origin: .zero, size: bounds.size),
            imagePixelSize: imagePixelSize
        )
        guard crop.width > 10,
              crop.height > 10,
              let cropped = cg.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    private func hideSelectionToolbar() {
        selectionToolbarView?.isHidden = true
        longCaptureButton?.isHidden = true
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
        let title = "单击选择窗口，或拖拽自定义截图区域"
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
