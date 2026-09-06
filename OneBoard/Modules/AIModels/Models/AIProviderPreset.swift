import Foundation

/// 连接模板参考 CC Switch 与各供应商文档；模型目录始终从当前 Key 实时读取。
struct AIProviderPreset: Identifiable {
    let id: String
    let title: String
    let baseURL: String
    var format: AIUpstreamAPIFormat = .openAIChat
    var quota: AIQuotaAPI = .none
    var claudeURL: String? = nil
    var website: String? = nil

    func address(for client: AIClient) -> String { client == .claude ? claudeURL ?? baseURL : baseURL }
    func apiFormat(for client: AIClient) -> AIUpstreamAPIFormat { client == .claude && claudeURL != nil ? .anthropic : format }
    var websiteURL: String {
        if let website { return website }
        var parts = URLComponents(string: baseURL)!
        parts.path = ""
        return parts.string!
    }

    static func find(_ id: String?) -> AIProviderPreset? { all.first { $0.id == id } }

    static func matching(_ profile: AIProviderProfile) -> AIProviderPreset? {
        guard profile.kind == .custom,
              profile.customUserAgent == nil, profile.requestHeaderOverridesJSON == nil,
              profile.requestBodyOverridesJSON == nil, profile.customEndpoints?.isEmpty != false,
              profile.runtimeMetadataJSON == nil, profile.runtimeSettingsJSON == nil,
              profile.quotaURL == nil else { return nil }
        return all.first {
            $0.address(for: profile.client).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                && $0.apiFormat(for: profile.client) == (profile.apiFormat ?? .recommendedValue(for: profile.client, baseURL: profile.baseURL))
                && (profile.quotaAPI == nil || profile.quotaAPI == .auto || profile.quotaAPI == $0.quota)
        }
    }

    static let all: [AIProviderPreset] = [
        .init(id: "openai", title: "OpenAI API", baseURL: "https://api.openai.com/v1", format: .openAIResponses, website: "https://platform.openai.com"),
        .init(id: "anthropic", title: "Anthropic API", baseURL: "https://api.anthropic.com/v1", format: .anthropic, website: "https://console.anthropic.com"),
        .init(id: "deepseek", title: "DeepSeek", baseURL: "https://api.deepseek.com/v1", quota: .deepseek, claudeURL: "https://api.deepseek.com/anthropic", website: "https://platform.deepseek.com"),
        .init(id: "gemini", title: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", website: "https://aistudio.google.com"),
        .init(id: "moonshot", title: "Kimi / Moonshot（中国）", baseURL: "https://api.moonshot.cn/v1", claudeURL: "https://api.moonshot.cn/anthropic", website: "https://platform.moonshot.cn"),
        .init(id: "kimi-coding", title: "Kimi For Coding", baseURL: "https://api.kimi.com/coding/v1", claudeURL: "https://api.kimi.com/coding", website: "https://www.kimi.com/code"),
        .init(id: "siliconflow-cn", title: "硅基流动（中国）", baseURL: "https://api.siliconflow.cn/v1", quota: .siliconflow),
        .init(id: "siliconflow-global", title: "SiliconFlow（国际）", baseURL: "https://api.siliconflow.com/v1", quota: .siliconflow),
        .init(id: "openrouter", title: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", quota: .openrouter),
        .init(id: "dashscope-cn", title: "阿里云百炼（中国）", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        .init(id: "dashscope-global", title: "阿里云百炼（国际）", baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
        .init(id: "zhipu-coding", title: "智谱 GLM Coding Plan", baseURL: "https://open.bigmodel.cn/api/coding/paas/v4", claudeURL: "https://open.bigmodel.cn/api/anthropic", website: "https://open.bigmodel.cn"),
        .init(id: "minimax-cn", title: "MiniMax（中国）", baseURL: "https://api.minimaxi.com/v1", claudeURL: "https://api.minimaxi.com/anthropic"),
        .init(id: "minimax-global", title: "MiniMax（国际）", baseURL: "https://api.minimax.io/v1", claudeURL: "https://api.minimax.io/anthropic"),
        .init(id: "nvidia", title: "NVIDIA NIM", baseURL: "https://integrate.api.nvidia.com/v1", website: "https://build.nvidia.com"),
        .init(id: "groq", title: "Groq", baseURL: "https://api.groq.com/openai/v1", website: "https://console.groq.com"),
        .init(id: "mistral", title: "Mistral AI", baseURL: "https://api.mistral.ai/v1", website: "https://console.mistral.ai"),
        .init(id: "together", title: "Together AI", baseURL: "https://api.together.ai/v1", website: "https://api.together.ai"),
        .init(id: "xai", title: "xAI / Grok", baseURL: "https://api.x.ai/v1", website: "https://console.x.ai"),
        .init(id: "qiniu", title: "七牛云 AI", baseURL: "https://api.qnaigc.com/v1"),
        .init(id: "ppio", title: "PPIO 派欧云", baseURL: "https://api.ppio.com/v3/openai", claudeURL: "https://api.ppio.com/anthropic"),
        .init(id: "atlascloud", title: "AtlasCloud", baseURL: "https://api.atlascloud.ai/v1")
    ]
}
