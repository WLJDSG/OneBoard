import Foundation

/// 应用全局常量
enum Constants {
    /// 应用名称
    static let appName = "OneBoard"

    /// 剪贴板轮询间隔（秒）
    static let pasteboardPollInterval: TimeInterval = 0.5

    /// 默认最大剪贴板条目数
    static let defaultMaxClipboardItems = 200

    /// 默认保留天数
    static let defaultRetentionDays = 30

    /// 弹出窗口默认宽度
    static let popoverWidth: CGFloat = 350
    /// 弹出窗口默认高度
    static let popoverHeight: CGFloat = 500

    /// 暂存区窗口宽度
    static let dropZoneWidth: CGFloat = 300
    /// 暂存区窗口高度
    static let dropZoneHeight: CGFloat = 200

    /// 摇动检测：时间窗口（秒）
    static let shakeWindowDuration: TimeInterval = 0.5
    /// 摇动检测：最少方向变化次数
    static let shakeMinDirectionChanges = 3
    /// 摇动检测：最少点数
    static let shakeMinPositions = 5

    /// 数据库文件名
    static let databaseFileName = "oneboard.sqlite"

    /// App Group 标识符（主应用与 Finder Sync Extension 通信）
    static let appGroupIdentifier = "group.com.oneboard.mac"

    /// ChatGPT/Codex macOS 桌面 App 标识符
    static let codexDesktopBundleIdentifier = "com.openai.codex"

    // MARK: - UserDefaults Keys

    struct UserDefaultsKeys {
        static let maxClipboardItems = "max_clipboard_items"
        static let retentionDays = "retention_days"
        static let launchAtLogin = "launch_at_login"
        static let ocrServiceType = "ocr_service_type"          // "apple" | "third_party"
        static let thirdPartyOCRAPIKey = "third_party_ocr_api_key"
        static let translationServiceType = "translation_service_type"  // "apple" | "google" | "deepseek"
        static let thirdPartyTranslationAPIKey = "third_party_translation_api_key"
        static let ocrLanguage = "ocr_language"                  // 默认 "zh-Hans"
        static let translationSourceLanguage = "translation_source_language" // 默认 ""（自动检测）
        static let translationTargetLanguage = "translation_target_language" // 默认 "en"
        static let hasCompletedOnboarding = "has_completed_onboarding"
        static let accessibilityPermissionEnabled = "accessibility_permission_enabled"
        static let screenRecordingPermissionEnabled = "screen_recording_permission_enabled"
        static let inputMonitoringPermissionEnabled = "input_monitoring_permission_enabled"
        static let notificationPermissionEnabled = "notification_permission_enabled"
        static let gatewayProfiles = "gateway_profiles"
        static let codexAccountProfiles = "codex_account_profiles"
        static let activeCodexAccountID = "active_codex_account_id"
        static let pendingCodexAccountID = "pending_codex_account_id"
        static let aiProviderProfiles = "ai_provider_profiles"
        static let activeCodexProviderID = "active_codex_provider_id"
        static let activeClaudeProviderID = "active_claude_provider_id"
        static let selectedSettingsTab = "selected_settings_tab"

        // 待办事项
        static let todoRetentionDays = "todo_retention_days"          // -1 永久, 7/14/30/90
        static let todoAutoRetractDelay = "todo_auto_retract_delay"   // 面板自动收起延迟（秒）
        static let todoShowNotifications = "todo_show_notifications"   // 到期提醒通知

        // Finder 新建文件
        static let enabledFileTypes = "enabled_file_types"             // 共享 UserDefaults

        // iCloud 与日历
        static let iCloudSyncEnabled = "icloud_sync_enabled"
        static let iCloudLastLocalChange = "icloud_last_local_change"
        static let iCloudLastSync = "icloud_last_sync"
        static let calendarWeekStart = "calendar_week_start"
        static let calendarShowInMenuBar = "calendar_show_in_menu_bar"
    }

    // MARK: - Notification Names

    struct NotificationNames {
        static let pasteboardDidChange = "OneBoardPasteboardDidChange"
        static let shakeGestureDetected = "OneBoardShakeGestureDetected"
        static let hotkeyShowClipboard = "OneBoardHotkeyShowClipboard"
        static let hotkeyCaptureScreenshot = "OneBoardHotkeyCaptureScreenshot"
        static let hotkeyShowFileShelf = "OneBoardHotkeyShowFileShelf"
        static let configurationDidSync = "OneBoardConfigurationDidSync"
        static let privateConfigurationDidChange = "OneBoardPrivateConfigurationDidChange"
    }
}

extension Notification.Name {
    static let oneBoardConfigurationDidSync = Notification.Name(Constants.NotificationNames.configurationDidSync)
    static let oneBoardPrivateConfigurationDidChange = Notification.Name(Constants.NotificationNames.privateConfigurationDidChange)
}
