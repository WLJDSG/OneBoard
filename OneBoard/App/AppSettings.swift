import SwiftUI

/// 应用设置集中管理
/// 使用 @AppStorage 在 UserDefaults 中持久化
enum AppSettings {

    // MARK: - 剪贴板设置

    /// 最大记录条数
    @AppStorage(Constants.UserDefaultsKeys.maxClipboardItems)
    static var maxClipboardItems: Int = Constants.defaultMaxClipboardItems

    /// 保留天数
    @AppStorage(Constants.UserDefaultsKeys.retentionDays)
    static var retentionDays: Int = Constants.defaultRetentionDays

    // MARK: - OCR 设置

    /// OCR 服务类型: "apple" | "third_party"
    @AppStorage(Constants.UserDefaultsKeys.ocrServiceType)
    static var ocrServiceType: String = "apple"

    /// 第三方 OCR API Key
    @AppStorage(Constants.UserDefaultsKeys.thirdPartyOCRAPIKey)
    static var thirdPartyOCRAPIKey: String = ""

    /// OCR 识别语言
    @AppStorage(Constants.UserDefaultsKeys.ocrLanguage)
    static var ocrLanguage: String = "zh-Hans"

    // MARK: - 翻译设置

    /// 翻译服务类型: "apple" | "third_party"
    @AppStorage(Constants.UserDefaultsKeys.translationServiceType)
    static var translationServiceType: String = "apple"

    /// 第三方翻译 API Key
    @AppStorage(Constants.UserDefaultsKeys.thirdPartyTranslationAPIKey)
    static var thirdPartyTranslationAPIKey: String = ""

    /// 翻译目标语言
    @AppStorage(Constants.UserDefaultsKeys.translationTargetLanguage)
    static var translationTargetLanguage: String = "en"

    // MARK: - 通用设置

    /// 是否已完成新手引导
    @AppStorage(Constants.UserDefaultsKeys.hasCompletedOnboarding)
    static var hasCompletedOnboarding: Bool = false

    /// 开机自启
    @AppStorage(Constants.UserDefaultsKeys.launchAtLogin)
    static var launchAtLogin: Bool = false
}