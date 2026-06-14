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
    }

    // MARK: - Notification Names

    struct NotificationNames {
        static let pasteboardDidChange = "OneBoardPasteboardDidChange"
        static let shakeGestureDetected = "OneBoardShakeGestureDetected"
        static let hotkeyShowClipboard = "OneBoardHotkeyShowClipboard"
        static let hotkeyCaptureScreenshot = "OneBoardHotkeyCaptureScreenshot"
        static let hotkeyShowFileShelf = "OneBoardHotkeyShowFileShelf"
    }
}
