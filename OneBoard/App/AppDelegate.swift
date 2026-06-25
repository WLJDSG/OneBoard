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
        PasteboardMonitor.shared.start()
        setupPasteboardObserver()
        DragDetector.shared.start()
        _ = FileStagingViewModel.shared
        _ = GatewayProfileStore.shared.initializeDefaultsIfNeeded()
        setupDefaultSettings()

        Task {
            await ClipboardRepository().applyRetentionPolicy()
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
        defaults.set(LaunchAtLogin.isEnabled, forKey: keys.launchAtLogin)
    }
}
