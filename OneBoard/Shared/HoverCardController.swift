import AppKit
import SwiftUI

final class HoverCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HoverCardController: ObservableObject {
    @Published var pinned = false
    private(set) var panel: NSPanel?
    weak var anchor: NSView?
    private var timer: Timer?
    private var outsideSince: Date?
    private var hoverSince: Date?
    private var suppressHover = false
    private let title: String
    private let size: CGSize
    private let content: () -> AnyView
    init(title: String, size: CGSize, content: @escaping () -> AnyView) {
        self.title = title; self.size = size; self.content = content
    }
    func attach(to anchor: NSView) {
        self.anchor = anchor
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPointer() }
        }
    }
    func toggle() {
        if panel?.isVisible == true { hide(); suppressHover = true }
        else { reveal() }
    }
    func reveal() {
        if panel == nil {
            let window = HoverCardPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = title
            window.backgroundColor = .clear; window.isOpaque = false
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: content().clipShape(RoundedRectangle(cornerRadius: 22)))
            panel = window
        }
        guard let panel else { return }
        if let frame = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.maxX - size.width - 10, y: frame.maxY - size.height - 8))
        }
        setPinned(pinned)
        panel.orderFrontRegardless()
        outsideSince = nil
    }
    func hide() { panel?.orderOut(nil); outsideSince = nil }
    func setPinned(_ value: Bool) { pinned = value; panel?.level = value ? .statusBar : .floating; panel?.hidesOnDeactivate = false }
    private func pollPointer() { updatePointer(NSEvent.mouseLocation, now: Date()) }
    func updatePointer(_ point: CGPoint, now: Date) {
        let rect = anchor.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } }
        let onIcon = rect?.contains(point) == true
        if !onIcon { suppressHover = false; hoverSince = nil }
        if onIcon && !suppressHover && panel?.isVisible != true {
            if let since = hoverSince {
                if now.timeIntervalSince(since) >= 0.7 { reveal() }
            } else { hoverSince = now }
        }
        guard let panel, panel.isVisible else { return }
        if onIcon || panel.frame.contains(point) || panel.attachedSheet != nil || pinned { outsideSince = nil; return }
        if let since = outsideSince, now.timeIntervalSince(since) > 0.35 { hide() }
        else if outsideSince == nil { outsideSince = now }
    }
}
