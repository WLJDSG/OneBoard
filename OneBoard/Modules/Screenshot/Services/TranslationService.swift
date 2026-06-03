import Foundation
import AppKit

/// 翻译服务协议
protocol TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String
}

/// Apple 内建翻译实现
/// 使用 NLLanguageRecognizer + 系统语言资源进行简单翻译
/// 注意：完整翻译功能需要 macOS 15.0+ 的 Translation 框架或第三方 API
final class AppleTranslationService: TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        // 当前使用占位实现，等待后续集成 Translation 框架
        // Translation 框架在 macOS 15.0+ 可用，需要作为 framework 链接
        throw TranslationServiceError.translationFailed("翻译功能需要 macOS 15.0+ 或配置第三方翻译 API。请在设置中配置第三方翻译服务。")
    }
}

/// 第三方翻译服务（扩展点）
final class ThirdPartyTranslationService: TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        // TODO: 对接第三方翻译 API（Google Translate、DeepL 等）
        throw TranslationServiceError.notImplemented
    }
}

enum TranslationServiceError: Error {
    case notImplemented
    case translationFailed(String)
}

/// 翻译服务工厂
enum TranslationServiceFactory {
    static func create() -> TranslationServiceProtocol {
        let serviceType = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.translationServiceType) ?? "apple"
        switch serviceType {
        case "third_party":
            return ThirdPartyTranslationService()
        default:
            return AppleTranslationService()
        }
    }
}