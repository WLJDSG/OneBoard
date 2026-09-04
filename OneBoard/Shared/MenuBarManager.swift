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
        button.contentTintColor = nil
        button.toolTip = Constants.appName
        button.setAccessibilityLabel(Constants.appName)
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.isVisible = true
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent, event.type != .rightMouseUp else { return }
        showMenu()
    }

    func showMenu(anchor: NSView? = nil) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .aqua)
        menu.delegate = self
        let aiModelsItem = NSMenuItem(title: "AI 模型", action: nil, keyEquivalent: "")
        aiModelsItem.image = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "AI 模型")
        aiModelsItem.submenu = makeAIModelMenu()
        menu.addItem(aiModelsItem)
        let codexItem = NSMenuItem(title: "Codex 账号", action: nil, keyEquivalent: "")
        codexItem.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: "Codex 账号")
        codexItem.submenu = makeCodexAccountMenu()
        menu.addItem(codexItem)
        menu.addItem(NSMenuItem.separator())
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
        let todoItem = NSMenuItem(title: "待办列表...", action: #selector(openTodoPanel), keyEquivalent: "")
        todoItem.target = self
        todoItem.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "待办")
        menu.addItem(todoItem)
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

    @objc private func openCodexAccountSettings() {
        Task { @MainActor in
            SettingsWindowManager.shared.show(selectedTab: .codexAccounts)
        }
    }

    @objc private func openAIModelSettings() {
        Task { @MainActor in
            SettingsWindowManager.shared.show(selectedTab: .aiModels)
        }
    }

    @objc private func selectAIModel(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let profileID = UUID(uuidString: value) else { return }
        Task { @MainActor in
            let message = AIModelSwitcherViewModel.shared.switchProfile(id: profileID)
            let alert = NSAlert()
            alert.messageText = "AI 模型"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func selectCodexAccount(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let accountID = UUID(uuidString: value) else { return }
        Task { @MainActor in
            let message = await CodexAccountViewModel.shared.requestSwitch(id: accountID)
            let alert = NSAlert()
            alert.messageText = "Codex 账号"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func openGatewaySwitcher() {
        Task { @MainActor in
            showGatewaySwitcherPanel()
        }
    }

    private func makeCodexAccountMenu() -> NSMenu {
        let submenu = NSMenu(title: "Codex 账号")
        let store = CodexAccountStore.shared
        let profiles = store.profiles
        let activeID = store.activeAccountID
        let pendingID = store.pendingAccountID

        if profiles.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无已保存账号", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for profile in profiles {
                let item = NSMenuItem(
                    title: profile.title,
                    action: #selector(selectCodexAccount(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.id.uuidString
                item.state = activeID == profile.id ? .on : .off
                if pendingID == profile.id {
                    item.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Codex 账号正在切换")
                }
                item.isEnabled = pendingID == nil && activeID != profile.id
                submenu.addItem(item)
            }
        }

        submenu.addItem(NSMenuItem.separator())
        let manageItem = NSMenuItem(
            title: "管理 Codex 账号...",
            action: #selector(openCodexAccountSettings),
            keyEquivalent: ""
        )
        manageItem.target = self
        manageItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "管理 Codex 账号")
        submenu.addItem(manageItem)
        return submenu
    }

    private func makeAIModelMenu() -> NSMenu {
        let root = NSMenu(title: "AI 模型")
        let store = AIProviderStore.shared
        let profiles = store.profiles

        for client in AIClient.allCases {
            let clientItem = NSMenuItem(title: client.title, action: nil, keyEquivalent: "")
            let clientMenu = NSMenu(title: client.title)
            let clientProfiles = profiles.filter { $0.client == client }
            let activeID = store.activeID(for: client)
            if clientProfiles.isEmpty {
                let empty = NSMenuItem(title: "暂无配置", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                clientMenu.addItem(empty)
            } else {
                for profile in clientProfiles {
                    let item = NSMenuItem(
                        title: "\(profile.title) · \(profile.model)",
                        action: #selector(selectAIModel(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = profile.id.uuidString
                    item.state = activeID == profile.id ? .on : .off
                    item.isEnabled = activeID != profile.id
                    clientMenu.addItem(item)
                }
            }
            clientItem.submenu = clientMenu
            root.addItem(clientItem)
        }

        root.addItem(NSMenuItem.separator())
        let manage = NSMenuItem(title: "管理 AI 模型...", action: #selector(openAIModelSettings), keyEquivalent: "")
        manage.target = self
        manage.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "管理 AI 模型")
        root.addItem(manage)
        return root
    }

    @objc private func openTodoPanel() {
        Task { @MainActor in
            TodoSlidePanelWindowManager.shared.toggle()
        }
    }

    @objc private func runUninstaller() {
        let alert = NSAlert()
        alert.messageText = "彻底卸载 OneBoard？"
        alert.informativeText = "将清理 Codex 账号凭据、AI 供应商密钥、隐私权限、菜单栏状态、偏好设置、缓存和当前 OneBoard.app，并退出应用。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "彻底卸载")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await SensitiveOperationAuthorizer().authorize(reason: "确认彻底卸载 OneBoard 并清理本机数据")
                LaunchAtLogin.isEnabled = false
                UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.launchAtLogin)
                try launchDeferredUninstaller()
                if let appDelegate = AppDelegate.shared {
                    appDelegate.requestTermination()
                } else {
                    NSApp.terminate(nil)
                }
            } catch {
                let failure = NSAlert()
                failure.messageText = "未能开始卸载"
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.addButton(withTitle: "好")
                failure.runModal()
            }
        }
    }

    private func launchDeferredUninstaller() throws {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.oneboard.mac"
        let appPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oneboard-uninstall-\(UUID().uuidString).sh")
        let script = deferredUninstallScript()

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, "\(pid)", bundleID, appPath]
        try task.run()
    }

    private func deferredUninstallScript() -> String {
        #"""
        #!/bin/bash
        set +e

        APP_PID="$1"
        CURRENT_BUNDLE_ID="$2"
        APP_PATH="$3"

        while kill -0 "$APP_PID" 2>/dev/null; do
            sleep 0.2
        done

        BUNDLE_IDS=(
            "$CURRENT_BUNDLE_ID"
            "com.oneboard.mac"
            "com.oneboard.mac.dev"
            "com.oneboard.mac.dev2"
            "com.oneboard.mac.Findersync"
            "com.oneboard.mac.Findersync.dev"
            "com.oneboard.mac.Findersync.dev2"
            "com.oneboard.mac-LaunchAtLoginHelper"
            "com.oneboard.mac.dev-LaunchAtLoginHelper"
            "com.oneboard.mac.dev2-LaunchAtLoginHelper"
        )
        TCC_SERVICES=(All Accessibility ScreenCapture ListenEvent SystemPolicyAllFiles SystemPolicyDesktopFolder SystemPolicyDocumentsFolder SystemPolicyDownloadsFolder AppleEvents UserNotifications)

        # 每个 Codex 账号对应一个同服务名的通用密码项；限制循环次数避免异常状态下无限重试。
        for ((INDEX=0; INDEX<100; INDEX++)); do
            /usr/bin/security delete-generic-password -s "com.oneboard.mac.codex-auth-cache" >/dev/null 2>&1 || break
        done
        for ((INDEX=0; INDEX<100; INDEX++)); do
            /usr/bin/security delete-generic-password -s "com.oneboard.mac.ai-provider-key" >/dev/null 2>&1 || break
        done

        for BID in "${BUNDLE_IDS[@]}"; do
            [ -z "$BID" ] && continue
            for SERVICE in "${TCC_SERVICES[@]}"; do
                /usr/bin/tccutil reset "$SERVICE" "$BID" >/dev/null 2>&1
            done
            /usr/bin/defaults delete "$BID" >/dev/null 2>&1
            /bin/rm -rf "$HOME/Library/Caches/$BID" >/dev/null 2>&1
            /bin/rm -rf "$HOME/Library/Application Support/$BID" >/dev/null 2>&1
            /bin/rm -rf "$HOME/Library/Saved Application State/$BID.savedState" >/dev/null 2>&1
            /bin/rm -rf "$HOME/Library/HTTPStorages/$BID" >/dev/null 2>&1
            /bin/rm -rf "$HOME/Library/Containers/$BID" >/dev/null 2>&1
            /bin/rm -f "$HOME/Library/Preferences/$BID.plist" >/dev/null 2>&1
        done

        # 辅助功能列表单独重试主 Bundle ID；此时 App 仍存在，tccutil 可解析代码签名。
        /usr/bin/tccutil reset Accessibility "$CURRENT_BUNDLE_ID" >/tmp/oneboard-uninstall-tcc.log 2>&1

        /bin/rm -rf "$HOME/Library/Group Containers/group.com.oneboard.mac" >/dev/null 2>&1
        /bin/rm -rf "$HOME/Library/Application Scripts/group.com.oneboard.mac" >/dev/null 2>&1
        /bin/rm -rf "$HOME/Library/Application Support/OneBoard" >/dev/null 2>&1

        # 当前 Helper 可在 sudoers 允许范围内自卸载，不再弹管理员密码框。
        /usr/bin/sudo -n /usr/local/bin/oneboard-gateway-helper --uninstall >/dev/null 2>&1

        /usr/bin/python3 - <<'PY' >/dev/null 2>&1
        import os
        import plistlib

        files = [
            os.path.expanduser('~/Library/Preferences/com.apple.controlcenter.plist'),
            os.path.expanduser('~/Library/Preferences/com.apple.universalaccessAuthWarning.plist'),
            os.path.expanduser('~/Library/Preferences/com.apple.corespotlightui.plist'),
        ]

        for path in files:
            if not os.path.exists(path):
                continue
            try:
                with open(path, 'rb') as f:
                    plist = plistlib.load(f)
            except Exception:
                continue

            changed = False
            if isinstance(plist.get('CSReceiverBundleIdentifierState'), dict):
                before = len(plist['CSReceiverBundleIdentifierState'])
                plist['CSReceiverBundleIdentifierState'] = {
                    k: v for k, v in plist['CSReceiverBundleIdentifierState'].items()
                    if 'oneboard' not in str(k).lower()
                }
                changed = changed or len(plist['CSReceiverBundleIdentifierState']) != before

            before = len(plist)
            plist = {
                k: v for k, v in plist.items()
                if 'oneboard' not in str(k).lower()
            }
            changed = changed or len(plist) != before

            if changed:
                try:
                    with open(path, 'wb') as f:
                        plistlib.dump(plist, f)
                except Exception:
                    pass
        PY

        /usr/bin/killall cfprefsd ControlCenter Dock >/dev/null 2>&1

        if [[ "$APP_PATH" == *.app && -d "$APP_PATH" ]]; then
            /bin/rm -rf "$APP_PATH" >/dev/null 2>&1
        fi

        /bin/rm -f "$0" >/dev/null 2>&1
        """#
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
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let blue = NSColor(calibratedRed: 0.18, green: 0.55, blue: 1.0, alpha: 1)
            let violet = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.98, alpha: 1)

            let rearPanel = NSBezierPath(
                roundedRect: NSRect(x: 6.0, y: 6.0, width: 9.5, height: 9.0),
                xRadius: 2.2,
                yRadius: 2.2
            )
            violet.setFill()
            rearPanel.fill()

            let frontPanel = NSBezierPath(
                roundedRect: NSRect(x: 2.5, y: 2.5, width: 11.5, height: 11.5),
                xRadius: 2.6,
                yRadius: 2.6
            )
            blue.setFill()
            frontPanel.fill()

            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setBlendMode(.clear)
                context.setLineCap(.round)
                context.setLineWidth(1.25)
                context.move(to: CGPoint(x: 5.2, y: 9.1))
                context.addLine(to: CGPoint(x: 11.0, y: 9.1))
                context.move(to: CGPoint(x: 5.2, y: 6.4))
                context.addLine(to: CGPoint(x: 9.2, y: 6.4))
                context.strokePath()
                context.restoreGState()
            }

            return true
        }
        image.isTemplate = false
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
        hostingView.layer?.cornerRadius = OneBoardRadius.lg
        hostingView.layer?.masksToBounds = true

        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: GatewaySwitcherPanelLayout.size),
            styleMask: [.borderless, .nonactivatingPanel],
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
            plistCleanHelper()
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
