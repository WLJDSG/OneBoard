import AppKit
import SwiftUI
import LaunchAtLogin

/// 剪贴板 / 网关浮动面板（复用类型）
private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 菜单栏 + 浮动窗口管理器
public final class MenuBarManager: NSObject, NSMenuDelegate {
    public static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var activeMenu: NSMenu?
    private var clipboardFloatingWindow: NSPanel?
    private var clipboardGlobalMouseMonitor: Any?
    private var clipboardAppDeactivateObserver: NSObjectProtocol?
    private var clipboardTargetApplication: NSRunningApplication?
    private var gatewayPanel: NSPanel?
    private var gatewayGlobalMouseMonitor: Any?
    private var gatewayAppDeactivateObserver: NSObjectProtocol?

    private override init() { super.init() }

    // MARK: - 菜单栏配置（statusItem 由 main.swift 预创建后传入）

    public func configure(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        guard let button = statusItem.button else { return }
        button.image = createMenuBarIcon()
        button.imagePosition = .imageOnly
        button.title = ""
        button.contentTintColor = .labelColor
        button.toolTip = Constants.appName
        button.setAccessibilityLabel(Constants.appName)
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.length = NSStatusItem.squareLength
        statusItem.isVisible = true
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent, event.type != .rightMouseUp else { return }
        showMenu()
    }

    func showMenu(anchor: NSView? = nil) {
        let menu = NSMenu()
        menu.delegate = self
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
        let uninstallItem = NSMenuItem(title: "彻底卸载并清理残留...", action: #selector(runUninstaller), keyEquivalent: "")
        uninstallItem.target = self
        uninstallItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "卸载")
        menu.addItem(uninstallItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 OneBoard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "退出")
        menu.addItem(quitItem)

        let anchorView = anchor ?? statusItem?.button
        if let anchorView {
            activeMenu = menu
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.minY - 4), in: anchorView)
        }
    }

    public func menuDidClose(_ menu: NSMenu) {
        if activeMenu === menu { activeMenu = nil }
    }

    @objc private func openSettings() {
        Task { @MainActor in
            SettingsWindowManager.shared.show()
        }
    }

    @objc private func openGatewaySwitcher() {
        Task { @MainActor in
            showGatewaySwitcherPanel()
        }
    }

    @objc private func runUninstaller() {
        let alert = NSAlert()
        alert.messageText = "彻底卸载 OneBoard？"
        alert.informativeText = "将清理所有隐私权限、菜单栏状态、偏好设置和缓存。\n应用本身需手动拖入垃圾桶。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "彻底卸载")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 执行与 uninstall.sh 相同的清理逻辑
        let bundleID = Bundle.main.bundleIdentifier ?? "com.oneboard.mac"

        // 1. UserDefaults
        UserDefaults.standard.removePersistentDomain(forName: bundleID)

        // 2. TCC
        let tccTasks = ["All", "Accessibility", "ScreenCapture", "SystemPolicyAllFiles"]
        for service in tccTasks {
            let task = Process()
            task.launchPath = "/usr/bin/tccutil"
            task.arguments = ["reset", service, bundleID]
            task.launch()
            task.waitUntilExit()
        }

        // 3. 清理 plist 中的 OneBoard 条目
        plistCleanHelper()

        // 4. 缓存
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/Library/Caches/\(bundleID)",
            "\(home)/Library/Application Support/\(bundleID)",
            "\(home)/Library/Saved Application State/\(bundleID).savedState",
            "\(home)/Library/HTTPStorages/\(bundleID)",
        ]
        for path in paths { try? fm.removeItem(atPath: path) }

        // 5. 重启 daemons
        for daemon in ["cfprefsd", "ControlCenter", "Dock"] {
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = [daemon]
            task.launch()
            task.waitUntilExit()
        }

        let done = NSAlert()
        done.messageText = "残留已清理完成"
        done.informativeText = "请将 OneBoard.app 拖入垃圾桶完成卸载。\n\n💡 提示：Launch Services 残留需要重启 Mac 才能完全清除。"
        done.alertStyle = .informational
        done.addButton(withTitle: "好")
        done.runModal()
    }

    /// 清理系统 plist 中的 OneBoard 条目
    private func plistCleanHelper() {
        let home = NSHomeDirectory()
        let files = [
            "\(home)/Library/Preferences/com.apple.controlcenter.plist",
            "\(home)/Library/Preferences/com.apple.universalaccessAuthWarning.plist",
            "\(home)/Library/Preferences/com.apple.corespotlightui.plist",
        ]
        for filePath in files {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            var changed = false
            if var dict = plist["CSReceiverBundleIdentifierState"] as? [String: Any] {
                let before = dict.count
                dict = dict.filter { !$0.key.lowercased().contains("oneboard") }
                if dict.count != before { changed = true; plist["CSReceiverBundleIdentifierState"] = dict }
            }
            let before = plist.count
            plist = plist.filter { !$0.key.lowercased().contains("oneboard") }
            if plist.count != before { changed = true }
            if changed {
                let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
                try? newData?.write(to: URL(fileURLWithPath: filePath))
            }
        }
    }

    @objc private func quitApp() {
        AppDelegate.shared?.requestTermination()
    }

    // MARK: - 图标

    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.5).setStroke()
            let back = NSBezierPath(
                roundedRect: NSRect(x: rect.minX + 3.0, y: rect.minY + 6.0, width: 9.0, height: 7.5),
                xRadius: 1.8, yRadius: 1.8
            )
            back.lineWidth = 1.5
            back.stroke()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let front = NSBezierPath(
                roundedRect: NSRect(x: rect.minX + 6.2, y: rect.minY + 3.7, width: 9.0, height: 7.5),
                xRadius: 1.8, yRadius: 1.8
            )
            front.lineWidth = 1.5
            front.fill()
            front.stroke()
            return true
        }
        image.isTemplate = true
        return image
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

        clipboardAppDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeClipboardFloatingWindow()
        }

        clipboardGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, let panel = self.clipboardFloatingWindow, panel.isVisible else { return }
            let clickLocation = NSEvent.mouseLocation
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

    // MARK: - 授权管理

    @MainActor
    func clearPrivacyAuthorizationsFromMenu() {
        clearPrivacyAuthorizations()
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
