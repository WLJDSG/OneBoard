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
        throw TranslationServiceError.translationFailed("当前 macOS 14 目标无法直接使用系统 Translation 框架。请配置第三方翻译 API，或升级项目目标到 macOS 15+ 后接入 Apple Translation。")
    }
}

/// 第三方翻译服务（扩展点）
final class ThirdPartyTranslationService: TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        try await DeepSeekTranslationClient().translate(
            text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }
}

/// DeepSeek 翻译客户端（OpenAI-compatible Chat Completions）
private struct DeepSeekTranslationClient {
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let model = "deepseek-v4-flash"

    func translate(_ text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String {
        let apiKey = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.thirdPartyTranslationAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else {
            throw TranslationServiceError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = DeepSeekRequest(
            model: model,
            messages: [
                .init(
                    role: "system",
                    content: "You are a professional translation engine. Translate accurately and return only the translated text. Do not explain."
                ),
                .init(
                    role: "user",
                    content: makePrompt(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
                )
            ],
            thinking: .init(type: "disabled"),
            temperature: 0.2,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.translationFailed("DeepSeek 未返回有效响应")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw TranslationServiceError.translationFailed("DeepSeek 翻译失败：\(message)")
        }

        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        let translated = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !translated.isEmpty else {
            throw TranslationServiceError.translationFailed("DeepSeek 返回了空翻译结果")
        }
        return translated
    }

    private func makePrompt(text: String, sourceLanguage: String?, targetLanguage: String) -> String {
        let source = sourceLanguage ?? "auto-detected language"
        return """
        Translate the following text from \(source) to \(languageName(targetLanguage)).

        Text:
        \(text)
        """
    }

    private func languageName(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "Simplified Chinese"
        case "zh-Hant": return "Traditional Chinese"
        case "en": return "English"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "fr": return "French"
        case "de": return "German"
        default: return code
        }
    }
}

private struct DeepSeekRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Thinking: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let thinking: Thinking
    let temperature: Double
    let stream: Bool
}

private struct DeepSeekResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

enum TranslationServiceError: LocalizedError {
    case notImplemented
    case missingAPIKey
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "第三方翻译暂未配置"
        case .missingAPIKey:
            return "请先在设置中填写 DeepSeek API Key"
        case .translationFailed(let message):
            return message
        }
    }
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
