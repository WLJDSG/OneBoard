import Foundation

struct AIModelCatalogService {
    var session: URLSession = .shared

    func fetch(url: URL, format: AIUpstreamAPIFormat, keyField: ClaudeAPIKeyField,
               key: String, userAgent: String = "", headersJSON: String = "") async throws -> [String] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if url.host == "api.deepseek.com" || format == .openAIChat || format == .openAIResponses {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else if format == .geminiNative {
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if keyField == .apiKey { request.setValue(key, forHTTPHeaderField: "x-api-key") }
            else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        }
        if !userAgent.isEmpty { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if !headersJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = headersJSON.data(using: .utf8),
                  let headers = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                throw AIProviderQuotaError("请求头必须是字符串键值组成的 JSON 对象")
            }
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderQuotaError("模型目录未返回 HTTP 响应") }
        guard (200..<300).contains(http.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let nested = root?["error"] as? [String: Any]
            let message = (nested?["message"] ?? root?["message"]) as? String ?? "请检查连接、Key 权限及供应商是否提供模型目录"
            let safe = key.isEmpty ? message : message.replacingOccurrences(of: key, with: "[已隐藏]")
            throw AIProviderQuotaError("模型目录 HTTP \(http.statusCode)：\(String(safe.prefix(240)))")
        }
        let models = AIProviderEditorView.parseModelIDs(data)
        return format == .geminiNative ? models.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 } : models
    }
}
