import Foundation

/// 请求地址与模型目录分别解析；完整推理端点不能直接拿来 GET 模型。
enum AIEndpointResolver {
    static func isComplete(_ address: String) -> Bool {
        let path = URLComponents(string: address)?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return ["chat/completions", "responses", "messages"].contains { path == $0 || path.hasSuffix("/" + $0) }
            || path.hasSuffix(":generateContent") || path.hasSuffix(":streamGenerateContent")
    }

    static func requestURL(baseURL: String, format: AIUpstreamAPIFormat, model: String, legacyFullURL: Bool = false) -> URL? {
        guard var parts = components(baseURL) else { return nil }
        if isComplete(baseURL) || legacyFullURL { return parts.url }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if parts.host == "api.deepseek.com", format == .anthropic, path.isEmpty || path == "v1" { path = "anthropic" }
        path = versioned(path, format: format)
        let suffix: String
        switch format {
        case .openAIChat: suffix = "chat/completions"
        case .openAIResponses: suffix = "responses"
        case .anthropic: suffix = "messages"
        case .geminiNative: suffix = "models/\(model):generateContent"
        }
        parts.path = "/" + path + "/" + suffix
        parts.fragment = nil
        return parts.url
    }

    static func catalogURL(baseURL: String, format: AIUpstreamAPIFormat = .openAIChat) -> URL? {
        guard var parts = components(baseURL) else { return nil }
        if parts.host?.lowercased() == "api.deepseek.com" {
            parts.path = "/models"
        } else {
            var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            for suffix in ["chat/completions", "responses", "messages", "models"] {
                if path == suffix { path = ""; break }
                if path.hasSuffix("/" + suffix) { path = String(path.dropLast(suffix.count + 1)); break }
            }
            if let range = path.range(of: "/models/"), path.hasSuffix(":generateContent") || path.hasSuffix(":streamGenerateContent") {
                path = String(path[..<range.lowerBound])
            }
            parts.path = "/" + versioned(path, format: format) + "/models"
        }
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    private static func components(_ address: String) -> URLComponents? {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts
    }

    private static func versioned(_ path: String, format: AIUpstreamAPIFormat) -> String {
        // 保留供应商已有版本（如智谱 v4、火山 v3），只补缺失的版本。
        if path.hasSuffix("/openai") { return path }
        let last = path.split(separator: "/").last.map(String.init) ?? ""
        if last.range(of: #"^v\d+(beta\d*|alpha\d*)?$"#, options: .regularExpression) != nil { return path }
        let version = format == .geminiNative ? "v1beta" : "v1"
        return [path, version].filter { !$0.isEmpty }.joined(separator: "/")
    }
}
