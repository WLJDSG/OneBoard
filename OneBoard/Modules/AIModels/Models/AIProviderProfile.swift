import Foundation

enum AIClient: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: return "terminal"
        case .claude: return "brain.head.profile"
        }
    }
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case official
    case custom

    var id: String { rawValue }
    var title: String { self == .official ? "官方" : "自定义 API" }
}

enum ClaudeAPIKeyField: String, Codable, CaseIterable, Identifiable {
    case authToken = "ANTHROPIC_AUTH_TOKEN"
    case apiKey = "ANTHROPIC_API_KEY"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum AIUpstreamAPIFormat: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openAIChat = "openai_chat"
    case openAIResponses = "openai_responses"
    case geminiNative = "gemini_native"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropic: return "Anthropic Messages"
        case .openAIChat: return "OpenAI Chat Completions"
        case .openAIResponses: return "OpenAI Responses"
        case .geminiNative: return "Gemini Native"
        }
    }

    static func defaultValue(for client: AIClient) -> AIUpstreamAPIFormat {
        client == .claude ? .anthropic : .openAIResponses
    }

    static func recommendedValue(for client: AIClient, baseURL: String) -> AIUpstreamAPIFormat {
        guard client == .codex,
              let host = URLComponents(string: baseURL)?.host?.lowercased(),
              host == "deepseek.com" || host.hasSuffix(".deepseek.com") else {
            return defaultValue(for: client)
        }
        return .openAIChat
    }
}

enum AIPromptCacheRouting: String, Codable, CaseIterable, Identifiable {
    case auto
    case enabled
    case disabled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "自动"
        case .enabled: return "启用"
        case .disabled: return "禁用"
        }
    }
}

struct AIProviderProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var client: AIClient
    var kind: AIProviderKind
    var title: String
    var note: String?
    var websiteURL: String?
    var baseURL: String
    var model: String
    var quotaAPI: AIQuotaAPI?
    var apiFormat: AIUpstreamAPIFormat?
    var isFullURL: Bool?
    var customUserAgent: String?
    var requestHeaderOverridesJSON: String?
    var requestBodyOverridesJSON: String?
    var promptCacheKey: String?
    var promptCacheRouting: AIPromptCacheRouting?
    var impersonateClaudeCode: Bool?
    var maxOutputTokens: Int?
    var endpointAutoSelect: Bool?
    var customEndpoints: [String]?
    var runtimeSettingsJSON: String?
    var runtimeMetadataJSON: String?
    var claudeAPIKeyField: ClaudeAPIKeyField
    var claudeHaikuModel: String?
    var claudeHaikuModelName: String?
    var claudeSonnetModel: String?
    var claudeSonnetModelName: String?
    var claudeOpusModel: String?
    var claudeOpusModelName: String?
    var claudeFableModel: String?
    var claudeFableModelName: String?
    var claudeSubagentModel: String?
    var sourceIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        client: AIClient,
        kind: AIProviderKind = .custom,
        title: String,
        note: String? = nil,
        websiteURL: String? = nil,
        baseURL: String = "",
        model: String,
        quotaAPI: AIQuotaAPI? = nil,
        apiFormat: AIUpstreamAPIFormat? = nil,
        isFullURL: Bool? = nil,
        customUserAgent: String? = nil,
        requestHeaderOverridesJSON: String? = nil,
        requestBodyOverridesJSON: String? = nil,
        promptCacheKey: String? = nil,
        promptCacheRouting: AIPromptCacheRouting? = nil,
        impersonateClaudeCode: Bool? = nil,
        maxOutputTokens: Int? = nil,
        endpointAutoSelect: Bool? = nil,
        customEndpoints: [String]? = nil,
        runtimeSettingsJSON: String? = nil,
        runtimeMetadataJSON: String? = nil,
        claudeAPIKeyField: ClaudeAPIKeyField = .authToken,
        claudeHaikuModel: String? = nil,
        claudeHaikuModelName: String? = nil,
        claudeSonnetModel: String? = nil,
        claudeSonnetModelName: String? = nil,
        claudeOpusModel: String? = nil,
        claudeOpusModelName: String? = nil,
        claudeFableModel: String? = nil,
        claudeFableModelName: String? = nil,
        claudeSubagentModel: String? = nil,
        sourceIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.client = client
        self.kind = kind
        self.title = title
        self.note = note
        self.websiteURL = websiteURL
        self.baseURL = baseURL
        self.model = model
        self.quotaAPI = quotaAPI
        self.apiFormat = apiFormat
        self.isFullURL = isFullURL
        self.customUserAgent = customUserAgent
        self.requestHeaderOverridesJSON = requestHeaderOverridesJSON
        self.requestBodyOverridesJSON = requestBodyOverridesJSON
        self.promptCacheKey = promptCacheKey
        self.promptCacheRouting = promptCacheRouting
        self.impersonateClaudeCode = impersonateClaudeCode
        self.maxOutputTokens = maxOutputTokens
        self.endpointAutoSelect = endpointAutoSelect
        self.customEndpoints = customEndpoints
        self.runtimeSettingsJSON = runtimeSettingsJSON
        self.runtimeMetadataJSON = runtimeMetadataJSON
        self.claudeAPIKeyField = claudeAPIKeyField
        self.claudeHaikuModel = claudeHaikuModel
        self.claudeHaikuModelName = claudeHaikuModelName
        self.claudeSonnetModel = claudeSonnetModel
        self.claudeSonnetModelName = claudeSonnetModelName
        self.claudeOpusModel = claudeOpusModel
        self.claudeOpusModelName = claudeOpusModelName
        self.claudeFableModel = claudeFableModel
        self.claudeFableModelName = claudeFableModelName
        self.claudeSubagentModel = claudeSubagentModel
        self.sourceIdentifier = sourceIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func validated() throws -> AIProviderProfile {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.note = Self.trimmedOptional(note)
        copy.websiteURL = Self.trimmedOptional(websiteURL)
        copy.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.customUserAgent = Self.trimmedOptional(customUserAgent)
        copy.requestHeaderOverridesJSON = Self.trimmedOptional(requestHeaderOverridesJSON)
        copy.requestBodyOverridesJSON = Self.trimmedOptional(requestBodyOverridesJSON)
        copy.promptCacheKey = Self.trimmedOptional(promptCacheKey)
        copy.customEndpoints = customEndpoints?.compactMap(Self.trimmedOptional).nilIfEmpty
        copy.claudeHaikuModel = Self.trimmedOptional(claudeHaikuModel)
        copy.claudeHaikuModelName = Self.trimmedOptional(claudeHaikuModelName)
        copy.claudeSonnetModel = Self.trimmedOptional(claudeSonnetModel)
        copy.claudeSonnetModelName = Self.trimmedOptional(claudeSonnetModelName)
        copy.claudeOpusModel = Self.trimmedOptional(claudeOpusModel)
        copy.claudeOpusModelName = Self.trimmedOptional(claudeOpusModelName)
        copy.claudeFableModel = Self.trimmedOptional(claudeFableModel)
        copy.claudeFableModelName = Self.trimmedOptional(claudeFableModelName)
        copy.claudeSubagentModel = Self.trimmedOptional(claudeSubagentModel)

        guard !copy.title.isEmpty else { throw AIModelSwitchError.invalidProfile("名称不能为空") }
        guard !copy.model.isEmpty else { throw AIModelSwitchError.invalidProfile("模型 ID 不能为空") }
        guard !copy.title.contains(where: \.isNewline),
              !copy.model.contains(where: \.isNewline),
              !(copy.note?.contains(where: \.isNewline) ?? false),
              !copy.claudeValues.contains(where: { $0.contains(where: \.isNewline) }) else {
            throw AIModelSwitchError.invalidProfile("名称、备注、模型 ID 和显示名不能换行")
        }

        if let websiteURL = copy.websiteURL {
            guard Self.isHTTPURL(websiteURL) else {
                throw AIModelSwitchError.invalidProfile("官网链接必须是有效的 HTTP(S) URL")
            }
        }

        if copy.kind == .custom {
            guard Self.isHTTPURL(copy.baseURL) else {
                throw AIModelSwitchError.invalidProfile("API 地址必须是有效的 HTTP(S) URL")
            }
        } else {
            copy.baseURL = ""
        }
        if let value = copy.maxOutputTokens, value <= 0 {
            throw AIModelSwitchError.invalidProfile("最大输出 Token 必须大于 0")
        }
        try Self.validateJSONObject(copy.requestHeaderOverridesJSON, field: "请求头覆盖")
        try Self.validateJSONObject(copy.requestBodyOverridesJSON, field: "请求体覆盖")
        return copy
    }

    private var claudeValues: [String] {
        [
            claudeHaikuModel, claudeHaikuModelName,
            claudeSonnetModel, claudeSonnetModelName,
            claudeOpusModel, claudeOpusModelName,
            claudeFableModel, claudeFableModelName,
            claudeSubagentModel,
        ].compactMap { $0 }
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func isHTTPURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return false }
        return true
    }

    private static func validateJSONObject(_ value: String?, field: String) throws {
        guard let value, let data = value.data(using: .utf8) else { return }
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw AIModelSwitchError.invalidProfile("\(field)必须是 JSON 对象")
        }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}

enum AIModelSwitchError: LocalizedError, Equatable {
    case invalidProfile(String)
    case profileNotFound
    case apiKeyMissing
    case unsafePath(String)
    case invalidConfiguration(String)
    case backupMissing(String)
    case storageFailure(String)
    case importFailure(String)
    case proxyFailure(String)
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let message): return message
        case .profileNotFound: return "模型配置不存在"
        case .apiKeyMissing: return "请输入 API Key"
        case .unsafePath(let path): return "拒绝写入符号链接配置：\(path)"
        case .invalidConfiguration(let message): return "配置文件无效：\(message)"
        case .backupMissing(let path): return "没有可恢复的备份：\(path)"
        case .storageFailure(let message): return "数据库操作失败：\(message)"
        case .importFailure(let message): return "CC Switch 导入失败：\(message)"
        case .proxyFailure(let message): return "本地代理失败：\(message)"
        case .activationFailed(let message): return message
        }
    }
}
