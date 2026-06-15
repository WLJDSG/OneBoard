import AppKit
import SwiftUI

@MainActor
final class OCRBubbleWindowManager {
    static let shared = OCRBubbleWindowManager()

    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private init() {}

    func show(text: String, relativeTo sourceFrame: NSRect?) {
        close()

        let hostingView = NSHostingView(
            rootView: OCRBubbleView(text: text) { [weak self] in
                self?.close()
            }
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        position(panel, relativeTo: sourceFrame)
        panel.orderFrontRegardless()

        installOutsideClickMonitors(for: panel)
        self.panel = panel
    }

    func close() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        panel?.close()
        panel = nil
    }

    private func installOutsideClickMonitors(for panel: NSPanel) {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel, !panel.frame.contains(event.locationInWindow) else { return }
            Task { @MainActor in self?.close() }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel else { return event }
            let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            if !panel.frame.contains(screenPoint) {
                Task { @MainActor in self?.close() }
            }
            return event
        }
    }

    private func position(_ panel: NSPanel, relativeTo sourceFrame: NSRect?) {
        let screenFrame = screenFrame(containing: sourceFrame)
        guard let sourceFrame else {
            FloatingWindowManager.positionAtTopRight(panel, offset: 28)
            return
        }

        let gap: CGFloat = 12
        var origin = NSPoint(
            x: sourceFrame.midX - panel.frame.width / 2,
            y: sourceFrame.minY - panel.frame.height - gap
        )
        if origin.y < screenFrame.minY {
            origin.y = sourceFrame.maxY + gap
        }
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, screenFrame.minY + 8), screenFrame.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func screenFrame(containing frame: NSRect?) -> NSRect {
        guard let frame else {
            return NSScreen.main?.visibleFrame ?? .zero
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame ?? .zero
    }
}

private struct OCRBubbleView: View {
    @State private var editableText: String
    @State private var isEditing = false
    let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        _editableText = State(initialValue: text)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("提取文字")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            Group {
                if isEditing {
                    TextEditor(text: $editableText)
                        .font(.system(size: 17, weight: .medium))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                } else {
                    ScrollView {
                        Text(editableText)
                            .font(.system(size: 17, weight: .medium))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 82)

            HStack(spacing: 10) {
                Spacer()
                Button(isEditing ? "完成" : "编辑") {
                    isEditing.toggle()
                }
                .buttonStyle(.borderedProminent)

                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editableText, forType: .string)
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 360, height: 230)
        .background(BubbleShape().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(BubbleShape().stroke(Color.black.opacity(0.12), lineWidth: 1))
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 14
        let pointerWidth: CGFloat = 20
        let pointerHeight: CGFloat = 12
        let body = rect.insetBy(dx: 0, dy: pointerHeight).offsetBy(dx: 0, dy: pointerHeight)

        path.addRoundedRect(in: body, cornerSize: CGSize(width: corner, height: corner))
        path.move(to: CGPoint(x: rect.midX - pointerWidth / 2, y: body.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + pointerWidth / 2, y: body.minY))
        path.closeSubpath()
        return path
    }
}
