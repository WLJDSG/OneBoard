import AppKit
import LaunchAtLogin

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) weak var shared: AppDelegate?

    private var shouldAllowTermination = false

    override public init() {
        super.init()
        Self.shared = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try DatabaseManager.shared.initialize()
            print("[AppDelegate] 数据库初始化成功")
        } catch {
            print("[AppDelegate] 数据库初始化失败: \(error)")
        }

        HotkeyManager.registerAll()
        TodoServiceProvider.register()
        PasteboardMonitor.shared.start()
        setupPasteboardObserver()
        DragDetector.shared.start()
        _ = FileStagingViewModel.shared
        _ = GatewayProfileStore.shared.initializeDefaultsIfNeeded()
        setupDefaultSettings()

        // Cmd+Q 修复：设置隐藏主菜单
        setupHiddenMainMenu()

        // 待办面板仅通过快捷键或菜单触发，不再创建屏幕顶部透明触发区。
        _ = TodoListViewModel.shared

        Task {
            await ClipboardRepository().applyRetentionPolicy()
            await TodoRepository().applyRetentionPolicy()

            // 检查过期待办
            let overdue = try? await TodoRepository().fetchOverdue()
            if let overdue, !overdue.isEmpty {
                await MainActor.run {
                    TodoReminderService.shared.notifyOverdue(items: overdue)
                }
            }
        }

        print("[AppDelegate] OneBoard 启动完成")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        PasteboardMonitor.shared.stop()
        DragDetector.shared.stop()
        print("[AppDelegate] OneBoard 已退出")
    }

    public func requestTermination() {
        shouldAllowTermination = true
        NSApp.terminate(nil)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return shouldAllowTermination ? .terminateNow : .terminateCancel
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Cmd+Q 修复

    /// 设置隐藏主菜单，使 Cmd+Q 在应用活跃时正常工作
    /// macOS 仅在前台应用时才处理其主菜单快捷键，
    /// 因此当 OneBoard 未获得焦点时 Cmd+Q 仍由其他应用处理
    private func setupHiddenMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let quitItem = NSMenuItem(
            title: "退出 OneBoard",
            action: #selector(handleQuitFromMainMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
        print("[AppDelegate] 隐藏主菜单已设置（Cmd+Q 修复）")
    }

    @objc private func handleQuitFromMainMenu() {
        requestTermination()
    }

    private func setupPasteboardObserver() {
        NotificationCenter.default.addObserver(
            forName: PasteboardMonitor.didDetectNewContent,
            object: nil, queue: .main
        ) { _ in print("[AppDelegate] 剪贴板内容已更新") }
    }

    private func setupDefaultSettings() {
        let defaults = UserDefaults.standard
        let keys = Constants.UserDefaultsKeys.self
        if defaults.object(forKey: keys.maxClipboardItems) == nil { defaults.set(Constants.defaultMaxClipboardItems, forKey: keys.maxClipboardItems) }
        if defaults.object(forKey: keys.retentionDays) == nil { defaults.set(Constants.defaultRetentionDays, forKey: keys.retentionDays) }
        if defaults.object(forKey: keys.ocrServiceType) == nil { defaults.set("apple", forKey: keys.ocrServiceType) }
        if defaults.object(forKey: keys.translationServiceType) == nil { defaults.set("third_party", forKey: keys.translationServiceType) }
        if defaults.object(forKey: keys.ocrLanguage) == nil { defaults.set("zh-Hans", forKey: keys.ocrLanguage) }
        if defaults.object(forKey: keys.translationSourceLanguage) == nil { defaults.set("", forKey: keys.translationSourceLanguage) }
        if defaults.object(forKey: keys.translationTargetLanguage) == nil { defaults.set("en", forKey: keys.translationTargetLanguage) }
        defaults.set(PermissionManager.shared.hasAccessibilityPermission, forKey: keys.accessibilityPermissionEnabled)
        defaults.set(PermissionManager.shared.hasScreenRecordingPermission, forKey: keys.screenRecordingPermissionEnabled)
        defaults.set(PermissionManager.shared.hasInputMonitoringPermission, forKey: keys.inputMonitoringPermissionEnabled)
        defaults.set(LaunchAtLogin.isEnabled, forKey: keys.launchAtLogin)

        // 待办默认设置
        if defaults.object(forKey: keys.todoRetentionDays) == nil { defaults.set(-1, forKey: keys.todoRetentionDays) }
        if defaults.object(forKey: keys.todoAutoRetractDelay) == nil { defaults.set(1.0, forKey: keys.todoAutoRetractDelay) }
        if defaults.object(forKey: keys.todoShowNotifications) == nil { defaults.set(true, forKey: keys.todoShowNotifications) }
    }
}
