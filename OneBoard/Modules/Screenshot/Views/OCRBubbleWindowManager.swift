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

        let panelSize = OCRBubbleLayout.panelSize(in: screenFrame(containing: sourceFrame))

        let hostingView = NSHostingView(
            rootView: OCRBubbleView(
                text: text,
                panelSize: panelSize,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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
        let panelFrame = panel.frame

        // 默认：居中，放在截图窗口下方
        var origin = NSPoint(
            x: sourceFrame.midX - panelFrame.width / 2,
            y: sourceFrame.minY - panelFrame.height - gap
        )

        // 下方不够 → 放上方
        if origin.y < screenFrame.minY {
            origin.y = sourceFrame.maxY + gap
        }
        // 上方也不够 → 放右侧
        if origin.y + panelFrame.height > screenFrame.maxY {
            origin.y = sourceFrame.midY - panelFrame.height / 2
            origin.x = sourceFrame.maxX + gap
        }
        // 右侧超出 → 放左侧
        if origin.x + panelFrame.width > screenFrame.maxX {
            origin.x = sourceFrame.minX - panelFrame.width - gap
        }

        // 最终 clamp
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - panelFrame.width - 8)
        origin.y = min(max(origin.y, screenFrame.minY + 8), screenFrame.maxY - panelFrame.height - 8)

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

enum OCRBubbleLayout {
    static func panelSize(in screenFrame: CGRect) -> CGSize {
        CGSize(
            width: min(440, max(320, screenFrame.width - 32)),
            height: min(320, max(220, screenFrame.height - 32))
        )
    }
}

struct OCRBubbleView: View {
    let panelSize: CGSize
    let onClose: () -> Void

    @State private var editableText: String
    @State private var isEditing = false

    init(text: String, panelSize: CGSize, onClose: @escaping () -> Void) {
        self.panelSize = panelSize
        self.onClose = onClose
        _editableText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeaturePanelHeader(title: "提取文字", subtitle: "核对识别结果，可编辑后复制", icon: "text.viewfinder") {
                FeaturePanelIconButton(icon: "xmark", title: "关闭", action: onClose)
            }

            Group {
                if isEditing {
                    TextEditor(text: $editableText)
                        .oneBoardFont(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(FeaturePalette.surface, in: RoundedRectangle(cornerRadius: OneBoardRadius.md))
                } else {
                    ScrollView {
                        Text(editableText)
                            .oneBoardFont(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                    }
                    .background(FeaturePalette.surface, in: RoundedRectangle(cornerRadius: OneBoardRadius.md))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Spacer()
                Button(isEditing ? "完成" : "编辑") {
                    isEditing.toggle()
                }
                .buttonStyle(SettingsActionStyle())

                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editableText, forType: .string)
                    onClose()
                }
                .buttonStyle(SettingsActionStyle(prominent: true))
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .featurePanelStyle()
    }
}
