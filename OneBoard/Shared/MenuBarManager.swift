import AppKit
import SwiftUI
import LaunchAtLogin

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
    private var gatewayPanel: NSPanel?
    private var gatewayGlobalMouseMonitor: Any?
    private var gatewayAppDeactivateObserver: NSObjectProtocol?
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
        let gatewayItem = NSMenuItem(title: "网关切换...", action: #selector(openGatewaySwitcher), keyEquivalent: "g")
        gatewayItem.target = self
        gatewayItem.image = NSImage(systemSymbolName: "network", accessibilityDescription: "网关切换")
        menu.addItem(gatewayItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        menu.addItem(settingsItem)

        let clearPrivacyItem = NSMenuItem(title: "清除 OneBoard 授权...", action: #selector(clearPrivacyAuthorizations), keyEquivalent: "")
        clearPrivacyItem.target = self
        clearPrivacyItem.image = NSImage(systemSymbolName: "lock.slash", accessibilityDescription: "清除授权")
        menu.addItem(clearPrivacyItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 OneBoard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "退出")
        menu.addItem(quitItem)

        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        }
    }

    // MARK: - 网关切换窗口

    @MainActor
    func toggleGatewaySwitcherPanel() {
        if let gatewayPanel, gatewayPanel.isVisible {
            closeGatewaySwitcherPanel()
        } else {
            showGatewaySwitcherPanel()
        }
    }

    @MainActor
    func showGatewaySwitcherPanel() {
        if let gatewayPanel, gatewayPanel.isVisible {
            gatewayPanel.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: GatewaySwitcherPanelView())
        hostingView.wantsLayer = true

        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView

        FloatingWindowManager.positionAtTopRight(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        gatewayPanel = panel

        gatewayAppDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeGatewaySwitcherPanel()
        }

        gatewayGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, let panel = self.gatewayPanel, panel.isVisible else { return }
            if !NSPointInRect(NSEvent.mouseLocation, panel.frame) {
                self.closeGatewaySwitcherPanel()
            }
        }
    }

    func closeGatewaySwitcherPanel() {
        gatewayPanel?.close()
        gatewayPanel = nil
        if let monitor = gatewayGlobalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            gatewayGlobalMouseMonitor = nil
        }
        if let observer = gatewayAppDeactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            gatewayAppDeactivateObserver = nil
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

    @objc private func openGatewaySwitcher() {
        Task { @MainActor in
            showGatewaySwitcherPanel()
        }
    }

    @objc private func clearPrivacyAuthorizations() {
        let confirm = NSAlert()
        confirm.messageText = "清除 OneBoard 授权？"
        confirm.informativeText = "可以仅清除辅助功能和屏幕录制，也可以同时卸载网关免密 Helper 并关闭开机自启。普通配置和网关 Profile 不会被删除。"
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "仅清除隐私权限")
        confirm.addButton(withTitle: "清除全部授权")
        confirm.addButton(withTitle: "取消")

        let choice = confirm.runModal()
        guard choice != .alertThirdButtonReturn else { return }

        var failures: [String] = []
        do {
            try PermissionManager.shared.resetPrivacyAuthorizations()
        } catch {
            failures.append(error.localizedDescription)
        }

        if choice == .alertSecondButtonReturn {
            do {
                try OneBoardGatewayHelper().uninstall()
            } catch {
                failures.append("网关 Helper 卸载失败：\(error.localizedDescription)")
            }
            LaunchAtLogin.isEnabled = false
            UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.launchAtLogin)
        }

        PermissionManager.shared.syncStoredPermissionStates()
        Task { @MainActor in
            SystemCapabilityViewModel.shared.refresh()
            GatewayViewModel.shared.refreshHelperStatus()
            NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
        }

        if failures.isEmpty {
            showPrivacyResetResult(
                title: "已清除 OneBoard 授权",
                message: choice == .alertSecondButtonReturn
                    ? "隐私权限、网关免密 Helper 和开机自启已清理。"
                    : "辅助功能和屏幕录制授权记录已清除。"
            )
        } else {
            showPrivacyResetResult(title: "部分授权清除失败", message: failures.joined(separator: "\n"))
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
