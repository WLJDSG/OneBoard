import Foundation
import CryptoKit

/// 仅调用内置的只读额度接口，不执行导入配置中的脚本。
enum AIQuotaAPI: String, Codable, CaseIterable, Identifiable {
    case auto, sub2api, deepseek, siliconflow, openrouter, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "暂未接入额度查询"
        case .auto: return "自动识别"
        case .sub2api: return "Sub2API"
        case .deepseek: return "DeepSeek"
        case .siliconflow: return "SiliconFlow"
        case .openrouter: return "OpenRouter"
        }
    }
}

struct AIQuotaSnapshot: Codable, Equatable {
    var balance: String
    var todayTokens: Int64?
    var totalTokens: Int64? = nil
    var todayCacheTokens: Int64? = nil
    var totalCacheTokens: Int64? = nil
    var fetchedAt: Date
    var credentialID: String
}

enum AIUsageIdentity {
    static func quota(profile: AIProviderProfile, key: String) -> String {
        let endpoint = try? AIProviderUsageService.endpoint(profile)
        let value = make(profile: profile, key: key) + "\n" + (endpoint?.0.absoluteString ?? "none") + "\n" + (endpoint?.1.rawValue ?? "none")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func make(profile: AIProviderProfile, key: String) -> String {
        let parts = URLComponents(string: profile.baseURL)
        let origin = (parts?.host?.lowercased() ?? profile.baseURL) + (parts?.port.map { ":\($0)" } ?? "")
        return SHA256.hash(data: Data((origin + "\n" + key).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AIProviderUsageService {
    var session: URLSession = .shared

    func query(profile: AIProviderProfile, key: String) async throws -> AIQuotaSnapshot {
        let (url, api) = try Self.endpoint(profile)
        guard !key.isEmpty else { throw AIModelSwitchError.apiKeyMissing }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AIProviderQuotaError("额度接口未返回 HTTP 响应")
        }
        guard (200..<300).contains(response.statusCode) else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let nested = root?["error"] as? [String: Any]
            let message = (root?["message"] ?? nested?["message"]) as? String
            let detail = message.map { String($0.replacingOccurrences(of: key, with: "[已隐藏]").prefix(240)) }
                ?? "请确认额度接口类型及 Key 权限"
            throw AIProviderQuotaError("额度查询 HTTP \(response.statusCode)：\(detail)")
        }
        return try Self.parse(data, api: api, credentialID: AIUsageIdentity.make(profile: profile, key: key))
    }

    static func endpoint(_ profile: AIProviderProfile) throws -> (URL, AIQuotaAPI) {
        guard var parts = URLComponents(string: profile.baseURL), let host = parts.host,
              ["https", "http"].contains(parts.scheme ?? "") else {
            throw AIProviderQuotaError("请求地址无效")
        }
        var api = profile.quotaAPI ?? .auto
        guard api != .none else { throw AIProviderQuotaError("该供应商暂未接入额度查询；可前往供应商控制台查看") }
        if let address = profile.quotaURL, !address.isEmpty {
            guard let custom = URLComponents(string: address), ["https", "http"].contains(custom.scheme ?? ""),
                  custom.host != nil, custom.user == nil, custom.password == nil, let url = custom.url else {
                throw AIProviderQuotaError("额度地址无效")
            }
            return (url, api)
        }
        if api == .auto {
            switch host.lowercased() {
            case "api.deepseek.com": api = .deepseek
            case "api.siliconflow.cn", "api.siliconflow.com": api = .siliconflow
            case "openrouter.ai": api = .openrouter
            default: api = .sub2api
            }
        }
        // 同源请求，保留反向代理前缀，移除模型请求路径。
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for suffix in ["/chat/completions", "/responses", "/messages", "/models"] {
            if path.hasSuffix(suffix) { path = String(path.dropLast(suffix.count)) }
        }
        if path == "v1" { path = "" }
        else if path.hasSuffix("/v1") { path = String(path.dropLast(3)) }
        let endpoint: String
        switch api {
        case .deepseek:
            // DeepSeek 的 Anthropic 兼容前缀只用于模型请求，余额接口位于源站根路径。
            if host.lowercased() == "api.deepseek.com" { path = "" }
            endpoint = "user/balance"
        case .siliconflow: endpoint = "v1/user/info"
        case .openrouter:
            if path == "api" { path = "" }
            endpoint = "api/v1/credits"
        default: endpoint = "v1/usage"
        }
        parts.path = "/" + [path, endpoint].filter { !$0.isEmpty }.joined(separator: "/")
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { throw AIProviderQuotaError("请求地址无效") }
        return (url, api)
    }

    static func parse(_ data: Data, api: AIQuotaAPI, credentialID: String, now: Date = Date()) throws -> AIQuotaSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderQuotaError("额度响应格式无效")
        }
        func number(_ value: Any?) -> Double? {
            let n = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
            return n.flatMap { $0.isFinite ? $0 : nil }
        }
        func amount(_ value: Double, _ unit: String) -> String { String(format: "%.4f %@", value, unit) }
        var balance: String?
        var today: Int64?
        let resolvedAPI: AIQuotaAPI
        if api == .auto {
            let info = root["data"] as? [String: Any]
            if root["balance_infos"] != nil { resolvedAPI = .deepseek }
            else if info?["totalBalance"] != nil { resolvedAPI = .siliconflow }
            else if info?["total_credits"] != nil { resolvedAPI = .openrouter }
            else { resolvedAPI = .sub2api }
        } else { resolvedAPI = api }
        switch resolvedAPI {
        case .deepseek:
            let infos = root["balance_infos"] as? [[String: Any]] ?? []
            let values = infos.compactMap { info -> String? in
                guard let value = number(info["total_balance"]), let currency = info["currency"] as? String else { return nil }
                return amount(value, currency)
            }
            if !values.isEmpty { balance = values.joined(separator: " · ") }
        case .siliconflow:
            if let info = root["data"] as? [String: Any], let value = number(info["totalBalance"]) {
                balance = "余额 \(value)（供应商计价单位）"
            }
        case .openrouter:
            if let info = root["data"] as? [String: Any], let total = number(info["total_credits"]), let used = number(info["total_usage"]) {
                balance = amount(total - used, "USD")
            }
        case .none: throw AIProviderQuotaError("该供应商暂未接入额度查询")
        case .auto, .sub2api:
            if (root["isValid"] as? Bool) == false { throw AIProviderQuotaError("供应商返回 Key 无效或不可用") }
            if let remaining = number(root["remaining"]) {
                balance = remaining < 0 ? "无限额（供应商返回）" : amount(remaining, root["unit"] as? String ?? "USD")
                if let name = root["planName"] as? String { balance = name + " · " + balance! }
            }
            let usage = root["usage"] as? [String: Any]
            if let day = usage?["today"] as? [String: Any], let tokens = number(day["total_tokens"]), tokens >= 0, tokens < Double(Int64.max) {
                today = Int64(tokens)
            }
            if balance == nil, today != nil { balance = "接口未提供余额" }
        }
        guard let balance else { throw AIProviderQuotaError("未识别到额度；该接口可能不支持此查询，请选择对应额度类型") }
        var result = AIQuotaSnapshot(balance: balance, todayTokens: today, fetchedAt: now, credentialID: credentialID)
        if let usage = root["usage"] as? [String: Any] {
            func count(_ section: String, _ field: String) -> Int64? {
                guard let item = usage[section] as? [String: Any], let value = number(item[field]), value >= 0, value < Double(Int64.max) else { return nil }
                return Int64(value)
            }
            result.totalTokens = count("total", "total_tokens")
            result.todayCacheTokens = count("today", "cache_read_tokens")
            result.totalCacheTokens = count("total", "cache_read_tokens")
        }
        return result
    }
}

struct AIProviderQuotaError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
