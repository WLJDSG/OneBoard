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

struct AIProviderProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var client: AIClient
    var kind: AIProviderKind
    var title: String
    var baseURL: String
    var model: String
    var claudeAPIKeyField: ClaudeAPIKeyField
    var claudeHaikuModel: String?
    var claudeSonnetModel: String?
    var claudeOpusModel: String?
    var sourceIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        client: AIClient,
        kind: AIProviderKind = .custom,
        title: String,
        baseURL: String = "",
        model: String,
        claudeAPIKeyField: ClaudeAPIKeyField = .authToken,
        claudeHaikuModel: String? = nil,
        claudeSonnetModel: String? = nil,
        claudeOpusModel: String? = nil,
        sourceIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.client = client
        self.kind = kind
        self.title = title
        self.baseURL = baseURL
        self.model = model
        self.claudeAPIKeyField = claudeAPIKeyField
        self.claudeHaikuModel = claudeHaikuModel
        self.claudeSonnetModel = claudeSonnetModel
        self.claudeOpusModel = claudeOpusModel
        self.sourceIdentifier = sourceIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func validated() throws -> AIProviderProfile {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.claudeHaikuModel = Self.trimmedOptional(claudeHaikuModel)
        copy.claudeSonnetModel = Self.trimmedOptional(claudeSonnetModel)
        copy.claudeOpusModel = Self.trimmedOptional(claudeOpusModel)

        guard !copy.title.isEmpty else { throw AIModelSwitchError.invalidProfile("名称不能为空") }
        guard !copy.model.isEmpty else { throw AIModelSwitchError.invalidProfile("模型 ID 不能为空") }
        guard !copy.title.contains(where: \.isNewline),
              !copy.model.contains(where: \.isNewline) else {
            throw AIModelSwitchError.invalidProfile("名称和模型 ID 不能换行")
        }

        if copy.kind == .custom {
            guard let components = URLComponents(string: copy.baseURL),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host != nil else {
                throw AIModelSwitchError.invalidProfile("API 地址必须是有效的 HTTP(S) URL")
            }
        } else {
            copy.baseURL = ""
        }
        return copy
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
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
        }
    }
}
