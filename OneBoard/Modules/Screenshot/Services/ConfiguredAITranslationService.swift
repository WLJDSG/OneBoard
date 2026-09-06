import Foundation

/// 翻译复用供应商连接和 SQLite 凭据；不切换 Codex/Claude 的活动配置。
struct ConfiguredAITranslationService: TranslationServiceProtocol {
    static let selectionKey = "translation_ai_provider_id"
    var providerID: UUID? = UserDefaults.standard.string(forKey: Self.selectionKey).flatMap(UUID.init(uuidString:))
    var session: URLSession = .shared

    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        guard let id = providerID,
              let profile = AIProviderStore.shared.profiles.first(where: { $0.id == id && $0.kind == .custom }) else {
            throw TranslationServiceError.translationFailed("请先选择已添加的 API Key")
        }
        let key = try SQLiteAIProviderSecretVault().load(for: profile.id)
        let request = try Self.request(profile: profile, key: key, text: text, source: sourceLanguage, target: targetLanguage)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranslationServiceError.translationFailed("\(profile.title) 翻译失败（HTTP \(code)），请检查模型和 API Key 权限")
        }
        let format = profile.apiFormat ?? .recommendedValue(for: profile.client, baseURL: profile.baseURL)
        let result = try Self.parse(data, format: format)
        if let usage = result.usage {
            try AIUsageStore.shared.record(AIUsageEvent(id: UUID().uuidString,
                credentialID: AIUsageIdentity.make(profile: profile, key: key), timestamp: Date().timeIntervalSince1970,
                input: usage.input, output: usage.output, cacheRead: usage.read, cacheCreation: usage.creation))
        }
        return result.text
    }

    static func request(profile: AIProviderProfile, key: String, text: String, source: String?, target: String) throws -> URLRequest {
        guard !key.isEmpty else { throw TranslationServiceError.missingAPIKey }
        let model = profile.model.replacingOccurrences(of: "[1M]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw TranslationServiceError.translationFailed("请先为该供应商配置默认模型") }
        let format = profile.apiFormat ?? .recommendedValue(for: profile.client, baseURL: profile.baseURL)
        let prompt = "Translate the following text from \(source ?? "auto-detected language") to \(target). Return only the translation, without explanations.\n\n\(text)"
        var body: [String: Any]
        switch format {
        case .openAIChat:
            body = ["model": model, "messages": [["role": "user", "content": prompt]], "stream": false]
        case .openAIResponses:
            body = ["model": model, "input": prompt, "stream": false]
        case .anthropic:
            body = ["model": model, "messages": [["role": "user", "content": prompt]], "max_tokens": profile.maxOutputTokens ?? 4096, "stream": false]
        case .geminiNative:
            body = ["contents": [["role": "user", "parts": [["text": prompt]]]]]
        }
        guard let url = AIEndpointResolver.requestURL(baseURL: profile.baseURL, format: format, model: model,
                                                      legacyFullURL: profile.isFullURL == true) else {
            throw TranslationServiceError.translationFailed("请求地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if format == .geminiNative { request.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        else if format == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if profile.claudeAPIKeyField == .apiKey { request.setValue(key, forHTTPHeaderField: "x-api-key") }
            else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        } else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let ua = profile.customUserAgent { request.setValue(ua, forHTTPHeaderField: "User-Agent") }
        if let raw = profile.requestHeaderOverridesJSON?.data(using: .utf8),
           let headers = try JSONSerialization.jsonObject(with: raw) as? [String: String] {
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        }
        if let raw = profile.requestBodyOverridesJSON?.data(using: .utf8),
           let overrides = try JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            body.merge(overrides) { _, value in value }
        }
        // 翻译解析为非流式，避免供应商配置中的 stream 覆盖导致无法解析。
        if format != .geminiNative { body["stream"] = false }
        if url.host == "api.deepseek.com", format == .openAIChat { body["thinking"] = ["type": "disabled"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    struct Usage { var input: Int64; var output: Int64; var read: Int64; var creation: Int64 }
    static func parse(_ data: Data, format: AIUpstreamAPIFormat) throws -> (text: String, usage: Usage?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationServiceError.translationFailed("翻译响应格式无效")
        }
        func texts(_ blocks: [[String: Any]]) -> String { blocks.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined() }
        let text: String
        switch format {
        case .openAIChat:
            let first = (root["choices"] as? [[String: Any]])?.first
            text = (first?["message"] as? [String: Any])?["content"] as? String ?? ""
        case .openAIResponses:
            text = (root["output"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "message" }
                .map { texts($0["content"] as? [[String: Any]] ?? []) }.joined()
        case .anthropic: text = texts(root["content"] as? [[String: Any]] ?? [])
        case .geminiNative:
            let first = (root["candidates"] as? [[String: Any]])?.first
            text = texts((first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [])
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationServiceError.translationFailed("供应商未返回翻译正文")
        }
        let raw = root[format == .geminiNative ? "usageMetadata" : "usage"] as? [String: Any]
        let usage = raw.map { u -> Usage in
            func n(_ key: String) -> Int64 { max(0, (u[key] as? NSNumber)?.int64Value ?? 0) }
            let details = (u["prompt_tokens_details"] ?? u["input_tokens_details"]) as? [String: Any]
            let read: Int64
            if format == .anthropic { read = n("cache_read_input_tokens") }
            else if format == .geminiNative { read = n("cachedContentTokenCount") }
            else if let cached = details?["cached_tokens"] as? NSNumber { read = max(0, cached.int64Value) }
            else { read = n("prompt_cache_hit_tokens") }
            let creation = n("cache_creation_input_tokens")
            let input = n("input_tokens") + n("prompt_tokens") + n("promptTokenCount")
            return Usage(input: format == .anthropic ? input : max(0, input - read),
                         output: n("output_tokens") + n("completion_tokens") + n("candidatesTokenCount") + n("thoughtsTokenCount"), read: read, creation: creation)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), usage)
    }
}
