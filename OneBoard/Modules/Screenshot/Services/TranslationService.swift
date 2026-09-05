import AppKit
import Foundation
import NaturalLanguage
import Translation

/// 翻译服务协议
protocol TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String
}

/// Apple 内建翻译实现
final class AppleTranslationService: TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        let source = try resolvedSourceLanguage(for: text, sourceLanguage: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        guard status != .unsupported else {
            throw TranslationServiceError.translationFailed("Apple Translation 不支持当前语言组合")
        }

        if #available(macOS 26.0, *) {
            let session = TranslationSession(installedSource: source, target: target)
            try await session.prepareTranslation()
            let response = try await session.translate(text)
            let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else {
                throw TranslationServiceError.translationFailed("Apple Translation 返回了空翻译结果")
            }
            return translated
        }

        throw TranslationServiceError.translationFailed("Apple Translation 服务层翻译需要 macOS 26+，请切换 Google/已配置 API，或升级系统后使用。")
    }

    private func resolvedSourceLanguage(for text: String, sourceLanguage: String?) throws -> Locale.Language {
        if let sourceLanguage, !sourceLanguage.isEmpty {
            return Locale.Language(identifier: sourceLanguage)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            throw TranslationServiceError.translationFailed("Apple Translation 无法识别源语言，请手动选择源语言")
        }
        return Locale.Language(identifier: language.rawValue)
    }
}

/// Google 免费 Web 翻译端点
final class GoogleTranslationService: TranslationServiceProtocol {
    private let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sourceLanguage ?? "auto"),
            URLQueryItem(name: "tl", value: googleLanguageCode(targetLanguage)),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]

        guard let url = components?.url else {
            throw TranslationServiceError.translationFailed("Google 翻译请求地址无效")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.translationFailed("Google 翻译未返回有效响应")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                throw TranslationServiceError.translationFailed(
                    "Google 翻译请求过于频繁，当前网络已被 Google 暂时限制。请稍后重试，或切换 Apple/已配置 API。"
                )
            }
            if httpResponse.value(forHTTPHeaderField: "Content-Type")?.localizedCaseInsensitiveContains("text/html") == true {
                throw TranslationServiceError.translationFailed(
                    "Google 翻译暂时不可用（HTTP \(httpResponse.statusCode)）。请稍后重试，或切换 Apple/已配置 API。"
                )
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw TranslationServiceError.translationFailed("Google 翻译失败：\(message)")
        }

        return try parseTranslationResponse(data)
    }

    private func googleLanguageCode(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return code
        }
    }

    private func parseTranslationResponse(_ data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [Any],
              let segments = root.first as? [Any] else {
            throw TranslationServiceError.translationFailed("Google 翻译返回格式异常")
        }

        let translated = segments.compactMap { segment -> String? in
            guard let values = segment as? [Any] else { return nil }
            return values.first as? String
        }.joined()
        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationServiceError.translationFailed("Google 翻译返回了空翻译结果")
        }
        return trimmed
    }
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
            return "请先在 AI 模型设置中添加并选择 API Key"
        case .translationFailed(let message):
            return message
        }
    }
}

/// 翻译服务工厂
enum TranslationServiceFactory {
    static func create(type: TranslationServiceType = .current()) -> TranslationServiceProtocol {
        switch type {
        case .apple:
            return AppleTranslationService()
        case .google:
            return GoogleTranslationService()
        case .deepSeek:
            return ConfiguredAITranslationService()
        }
    }
}
