import AppKit
import SwiftUI

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TranslationPanelDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct TranslationPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> TranslationPanelDragView {
        TranslationPanelDragView()
    }

    func updateNSView(_ nsView: TranslationPanelDragView, context: Context) {}
}

@MainActor
final class TranslationPanelWindowManager {
    static let shared = TranslationPanelWindowManager()

    private var panel: NSPanel?
    private var translationTask: Task<Void, Never>?

    private init() {}

    func show(sourceText: String, relativeTo sourceFrame: NSRect? = nil) {
        closePanel()

        let viewModel = TranslationPanelViewModel(sourceText: sourceText)
        let hostingView = NSHostingView(
            rootView: TranslationPanelView(
                viewModel: viewModel,
                onTranslate: { [weak self, weak viewModel] in
                    guard let viewModel else { return }
                    self?.startTranslation(for: viewModel)
                },
                onSelectService: { [weak self, weak viewModel] serviceType in
                    guard let viewModel else { return }
                    self?.selectService(serviceType, for: viewModel)
                },
                onClose: { [weak self] in
                    self?.closePanel()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false

        position(panel, relativeTo: sourceFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel

        startTranslation(for: viewModel)
    }

    private func closePanel() {
        translationTask?.cancel()
        translationTask = nil
        panel?.close()
        panel = nil
    }

    private func startTranslation(for viewModel: TranslationPanelViewModel) {
        translationTask?.cancel()
        translationTask = Task { await viewModel.translate() }
    }

    private func selectService(_ serviceType: TranslationServiceType, for viewModel: TranslationPanelViewModel) {
        guard serviceType != viewModel.translationServiceType else { return }
        translationTask?.cancel()
        translationTask = Task { await viewModel.selectService(serviceType) }
    }

    private func position(_ panel: NSPanel, relativeTo sourceFrame: NSRect?) {
        if let sourceFrame {
            let screenFrame = screenFrame(containing: sourceFrame)
            let gap: CGFloat = 38
            var x = sourceFrame.maxX + gap
            let y = sourceFrame.midY - panel.frame.height / 2

            if x + panel.frame.width > screenFrame.maxX {
                x = sourceFrame.minX - panel.frame.width - gap
            }
            if x < screenFrame.minX {
                x = screenFrame.maxX - panel.frame.width - 8
            }

            let maxOriginY = max(screenFrame.minY, screenFrame.maxY - panel.frame.height)
            let clampedY = min(max(y, screenFrame.minY), maxOriginY)
            panel.setFrameOrigin(NSPoint(x: x, y: clampedY))
        } else {
            FloatingWindowManager.positionAtTopRight(panel, offset: 28)
        }
    }

    private func screenFrame(containing frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame ?? .zero
    }
}
