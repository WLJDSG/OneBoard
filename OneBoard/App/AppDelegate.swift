import AppKit
import SwiftUI
import LaunchAtLogin

/// AppDelegate - 管理应用生命周期
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 尽早设置 activation policy，避免 SwiftUI App 初始化覆盖
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 确保菜单栏应用激活策略已设置（applicationWillFinishLaunching 已设置）
        NSApp.setActivationPolicy(.accessory)

        // 2. 初始化数据库
        do {
            try DatabaseManager.shared.initialize()
            print("[AppDelegate] 数据库初始化成功")
        } catch {
            print("[AppDelegate] 数据库初始化失败: \(error)")
        }

        // 3. 设置菜单栏
        MenuBarManager.shared.setup()
        MenuBarManager.shared.onSettings = {
            Task { @MainActor in
                SettingsWindowManager.shared.show()
            }
        }

        // 4. 注册全局快捷键
        HotkeyManager.registerAll()

        // 5. 启动剪贴板监控
        PasteboardMonitor.shared.start()
        setupPasteboardObserver()

        // 6. 启动拖拽检测 + 强制初始化暂存区 ViewModel（注册摇动通知监听）
        DragDetector.shared.start()
        _ = FileStagingViewModel.shared  // 触发 lazy init，注册 DragDetector 通知 observer
        _ = GatewayProfileStore.shared.initializeDefaultsIfNeeded()

        // 7. 设置默认 UserDefaults
        setupDefaultSettings()

        // 8. 应用启动时的保留策略清理
        Task {
            await ClipboardRepository().applyRetentionPolicy()
        }

        print("[AppDelegate] OneBoard 启动完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        PasteboardMonitor.shared.stop()
        DragDetector.shared.stop()
        print("[AppDelegate] OneBoard 已退出")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 剪贴板变化监听

    private func setupPasteboardObserver() {
        // PasteboardMonitor 已直接保存到数据库，这里只需做日志记录
        NotificationCenter.default.addObserver(
            forName: PasteboardMonitor.didDetectNewContent,
            object: nil,
            queue: .main
        ) { _ in
            print("[AppDelegate] 剪贴板内容已更新")
        }
    }

    // MARK: - 默认设置

    private func setupDefaultSettings() {
        let defaults = UserDefaults.standard
        let keys = Constants.UserDefaultsKeys.self

        if defaults.object(forKey: keys.maxClipboardItems) == nil {
            defaults.set(Constants.defaultMaxClipboardItems, forKey: keys.maxClipboardItems)
        }
        if defaults.object(forKey: keys.retentionDays) == nil {
            defaults.set(Constants.defaultRetentionDays, forKey: keys.retentionDays)
        }
        if defaults.object(forKey: keys.ocrServiceType) == nil {
            defaults.set("apple", forKey: keys.ocrServiceType)
        }
        if defaults.object(forKey: keys.translationServiceType) == nil {
            defaults.set("third_party", forKey: keys.translationServiceType)
        }
        if defaults.object(forKey: keys.ocrLanguage) == nil {
            defaults.set("zh-Hans", forKey: keys.ocrLanguage)
        }
        if defaults.object(forKey: keys.translationSourceLanguage) == nil {
            defaults.set("", forKey: keys.translationSourceLanguage)
        }
        if defaults.object(forKey: keys.translationTargetLanguage) == nil {
            defaults.set("en", forKey: keys.translationTargetLanguage)
        }
        defaults.set(PermissionManager.shared.hasAccessibilityPermission, forKey: keys.accessibilityPermissionEnabled)
        defaults.set(PermissionManager.shared.hasScreenRecordingPermission, forKey: keys.screenRecordingPermissionEnabled)
        defaults.set(LaunchAtLogin.isEnabled, forKey: keys.launchAtLogin)
    }
}
