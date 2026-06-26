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

        // 根据文字内容计算弹窗尺寸
        let font = NSFont.systemFont(ofSize: 17, weight: .medium)
        let panelWidth: CGFloat = 380
        let textMaxWidth = panelWidth - 36  // 左右各 18 padding
        let textHeight = (text as NSString).boundingRect(
            with: NSSize(width: textMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height

        // 头部 ~40px + 间距 14 + 底部按钮 ~36px + 间距 + padding 36 = ~130px 固定开销
        // 文字区域最小 82px
        let contentBodyHeight = max(textHeight + 40, 82)
        let pointerHeight: CGFloat = 12
        let totalHeight = min(max(contentBodyHeight + 130, 200), 520)

        let hostingView = NSHostingView(
            rootView: OCRBubbleView(
                text: text,
                panelSize: CGSize(width: panelWidth, height: totalHeight),
                pointerHeight: pointerHeight,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: totalHeight),
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

private struct OCRBubbleView: View {
    let text: String
    let panelSize: CGSize
    let pointerHeight: CGFloat
    let onClose: () -> Void

    @State private var editableText: String
    @State private var isEditing = false

    init(text: String, panelSize: CGSize, pointerHeight: CGFloat, onClose: @escaping () -> Void) {
        self.text = text
        self.panelSize = panelSize
        self.pointerHeight = pointerHeight
        self.onClose = onClose
        _editableText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("提取文字")
                    .oneBoardFont(.title)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .oneBoardFont(.headline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            Group {
                if isEditing {
                    TextEditor(text: $editableText)
                        .oneBoardFont(.title)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                } else {
                    ScrollView {
                        Text(editableText)
                            .oneBoardFont(.title)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

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
        .frame(width: panelSize.width, height: panelSize.height)
        .background(
            BubbleShape(pointerHeight: pointerHeight)
                .fill(OneBoardColors.background)
        )
        .overlay(
            BubbleShape(pointerHeight: pointerHeight)
                .stroke(OneBoardShadow.md.color, lineWidth: 1)
        )
    }
}

private struct BubbleShape: Shape {
    let pointerHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = OneBoardRadius.xl
        let pointerWidth: CGFloat = 20
        let body = rect.insetBy(dx: 0, dy: pointerHeight).offsetBy(dx: 0, dy: pointerHeight)

        path.addRoundedRect(in: body, cornerSize: CGSize(width: corner, height: corner))
        path.move(to: CGPoint(x: rect.midX - pointerWidth / 2, y: body.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + pointerWidth / 2, y: body.minY))
        path.closeSubpath()
        return path
    }
}
