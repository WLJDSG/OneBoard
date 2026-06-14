import AppKit
import SwiftUI

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 菜单栏管理器
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem!
    private var clipboardFloatingWindow: NSPanel?
    private var clipboardGlobalMouseMonitor: Any?  // 全局鼠标点击监听
    private var clipboardAppDeactivateObserver: NSObjectProtocol?  // 应用失活监听
    private var clipboardTargetApplication: NSRunningApplication?
    var onSettings: (() -> Void)?

    private override init() { super.init() }

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = Constants.appName
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            return
        }
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clearPrivacyItem = NSMenuItem(title: "清除隐私授权...", action: #selector(clearPrivacyAuthorizations), keyEquivalent: "")
        clearPrivacyItem.target = self
        menu.addItem(clearPrivacyItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 OneBoard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        }
    }

    // MARK: - 浮动剪贴板窗口

    func showClipboardAsFloatingWindow() {
        if let existing = clipboardFloatingWindow, existing.isVisible {
            closeClipboardFloatingWindow(); return
        }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        clipboardTargetApplication = frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmostApplication

        let hostingView = ClipboardTrackingHostingView(
            rootView: ClipboardPopoverView(),
            onMouseExit: { [weak self] in
                self?.closeClipboardFloatingWindow()
            }
        )
        hostingView.wantsLayer = true

        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.popoverWidth, height: Constants.popoverHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView

        FloatingWindowManager.positionAtTopRight(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        clipboardFloatingWindow = panel

        // 监听应用失活（用户点击其他 App、Cmd+Tab 切换等）→ 关闭剪贴板
        clipboardAppDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeClipboardFloatingWindow()
        }

        // 全局鼠标按下监听：点击剪贴板窗口外部时关闭
        clipboardGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, let panel = self.clipboardFloatingWindow, panel.isVisible else { return }
            // 使用屏幕坐标判断点击是否在剪贴板窗口外
            let clickLocation = NSEvent.mouseLocation  // 屏幕坐标系
            if !NSPointInRect(clickLocation, panel.frame) {
                self.closeClipboardFloatingWindow()
            }
        }
    }

    func closeClipboardFloatingWindow() {
        clipboardFloatingWindow?.close()
        clipboardFloatingWindow = nil
        if let monitor = clipboardGlobalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            clipboardGlobalMouseMonitor = nil
        }
        if let observer = clipboardAppDeactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            clipboardAppDeactivateObserver = nil
        }
    }

    func targetApplicationForClipboardPaste() -> NSRunningApplication? {
        if let clipboardTargetApplication, !clipboardTargetApplication.isTerminated {
            return clipboardTargetApplication
        }
        return NSWorkspace.shared.runningApplications.first { app in
            app.isActive && app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    // MARK: - Actions

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func clearPrivacyAuthorizations() {
        let confirm = NSAlert()
        confirm.messageText = "清除 OneBoard 的隐私授权？"
        confirm.informativeText = "这会清除辅助功能和屏幕录制授权记录。下次使用相关功能时，macOS 会重新请求授权。"
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "清除授权")
        confirm.addButton(withTitle: "取消")

        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try PermissionManager.shared.resetPrivacyAuthorizations()
            showPrivacyResetResult(title: "已清除隐私授权", message: "辅助功能和屏幕录制授权记录已清除。")
        } catch {
            showPrivacyResetResult(title: "清除授权失败", message: error.localizedDescription)
        }
    }

    private func showPrivacyResetResult(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func createMenuBarIcon() -> NSImage {
        let icon = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: Constants.appName)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        icon.isTemplate = true
        return icon
    }
}

/// 带鼠标追踪的 NSHostingView —— 光标离开时触发回调
private final class ClipboardTrackingHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    private var onMouseExit: (() -> Void)?

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    convenience init(rootView: Content, onMouseExit: @escaping () -> Void) {
        self.init(rootView: rootView)
        self.onMouseExit = onMouseExit
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExit?()
    }
}
