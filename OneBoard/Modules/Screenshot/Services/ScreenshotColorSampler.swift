import AppKit

struct ScreenshotSampledColor: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    var text: String { "RGB(\(red), \(green), \(blue))" }
    var color: NSColor { NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1) }
}

/// 坐标采用 AppKit 屏幕坐标；像素采样使用原始截图，避免吸到遮罩或取色提示自身。
struct ScreenshotColorSurface {
    let image: NSImage
    let frame: CGRect
    private let bitmap: NSBitmapImageRep

    init?(image: NSImage, frame: CGRect) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let normalized = context.makeImage() else { return nil }
        self.image = image; self.frame = frame
        bitmap = NSBitmapImageRep(cgImage: normalized)
    }

    func sample(at point: CGPoint) -> ScreenshotSampledColor? {
        guard frame.width > 0, frame.height > 0, frame.contains(point) else { return nil }
        let x = min(bitmap.pixelsWide - 1, Int((point.x - frame.minX) / frame.width * CGFloat(bitmap.pixelsWide)))
        let y = min(bitmap.pixelsHigh - 1, Int((frame.maxY - point.y) / frame.height * CGFloat(bitmap.pixelsHigh)))
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
        return ScreenshotSampledColor(red: Int((color.redComponent * 255).rounded()),
                                      green: Int((color.greenComponent * 255).rounded()),
                                      blue: Int((color.blueComponent * 255).rounded()))
    }
}

@MainActor
final class ScreenshotColorSampler {
    static let shared = ScreenshotColorSampler()
    var surfaces: [ScreenshotColorSurface] = []
    private var panels: [NSPanel] = []
    private var completion: ((NSColor) -> Void)?
    private var previousKeyWindow: NSWindow?
    private var isPreparing = false

    func begin(onPick: @escaping (NSColor) -> Void) {
        guard panels.isEmpty, !isPreparing else { return }
        isPreparing = true
        Task { @MainActor in
            var sources = surfaces
            if sources.isEmpty {
                let capture = ScreenshotCaptureService()
                for (index, screen) in NSScreen.screens.enumerated() {
                    if let image = await capture.captureDisplay(displayNumber: index + 1),
                       let surface = ScreenshotColorSurface(image: image, frame: screen.frame) { sources.append(surface) }
                }
            }
            isPreparing = false
            guard !sources.isEmpty else { NSSound.beep(); return }
            previousKeyWindow = NSApp.keyWindow
            completion = onPick
            for surface in sources {
                let panel = ColorSamplerPanel(contentRect: surface.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.isOpaque = true; panel.hasShadow = false
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = ColorSamplerView(surface: surface, finish: { [weak self] in self?.finish($0) })
                panel.contentView = view
                panel.acceptsMouseMovedEvents = true
                panels.append(panel)
                panel.orderFrontRegardless()
                if surface.frame.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
            }
        }
    }

    private func finish(_ color: NSColor?) {
        let callback = completion
        completion = nil
        panels.forEach { $0.orderOut(nil); $0.close() }; panels.removeAll()
        previousKeyWindow?.makeKey(); previousKeyWindow = nil
        if let color { callback?(color) }
    }
}

private final class ColorSamplerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class ColorSamplerView: NSView {
    let surface: ScreenshotColorSurface
    let finish: (NSColor?) -> Void
    private var point = NSEvent.mouseLocation
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(surface: ScreenshotColorSurface, finish: @escaping (NSColor?) -> Void) {
        self.surface = surface; self.finish = finish
        super.init(frame: CGRect(origin: .zero, size: surface.frame.size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { window?.makeKey(); window?.makeFirstResponder(self); mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) { point = NSEvent.mouseLocation; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { finish(surface.sample(at: NSEvent.mouseLocation)?.color) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(nil); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c",
           let sampled = surface.sample(at: NSEvent.mouseLocation) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sampled.text, forType: .string)
            finish(sampled.color)
            return
        }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
        keyDown(with: event); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        surface.image.draw(in: bounds)
        guard let sampled = surface.sample(at: point) else { return }
        let local = CGPoint(x: point.x - surface.frame.minX, y: point.y - surface.frame.minY)
        let panel = CGRect(x: max(8, min(local.x + 20, bounds.maxX - 242)),
                           y: max(8, min(local.y - 82, bounds.maxY - 80)), width: 234, height: 72)
        NSColor.black.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 12, yRadius: 12).fill()
        sampled.color.setFill()
        NSBezierPath(roundedRect: CGRect(x: panel.minX + 12, y: panel.minY + 34, width: 20, height: 20), xRadius: 4, yRadius: 4).fill()
        (sampled.text as NSString).draw(at: CGPoint(x: panel.minX + 42, y: panel.minY + 36), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
        ("⌘C 复制 · 单击取色 · Esc 取消" as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.minY + 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.lightGray])
    }
}
