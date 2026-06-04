import AppKit

/// 浮动窗口管理器 - 创建可复用的置顶 NSPanel
final class FloatingWindowManager {

    /// 创建浮动面板
    /// - Parameters:
    ///   - contentView: 内容视图（NSHostingView）
    ///   - width: 窗口宽度
    ///   - height: 窗口高度
    ///   - title: 窗口标题
    /// - Returns: NSPanel 实例
    static func createFloatingPanel(
        contentView: NSView,
        width: CGFloat,
        height: CGFloat,
        title: String = ""
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = contentView
        panel.backgroundColor = NSColor.windowBackgroundColor

        return panel
    }

    /// 创建全屏遮罩窗口（用于截图区域选择）
    static func createFullScreenOverlay(contentView: NSView) -> NSPanel {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let panel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.contentView = contentView

        return panel
    }

    /// 居中窗口在屏幕上
    static func centerWindow(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let x = screenFrame.midX - windowFrame.width / 2
        let y = screenFrame.midY - windowFrame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 将窗口放在屏幕右上角（兼容菜单栏 app 无 key window 场景）
    static func positionAtTopRight(_ window: NSWindow, offset: CGFloat = 20) {
        // 优先鼠标所在屏幕，回退主屏幕，再回退第一个屏幕
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let x = screenFrame.maxX - windowFrame.width - offset
        let y = screenFrame.maxY - windowFrame.height - offset
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}