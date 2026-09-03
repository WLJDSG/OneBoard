import Foundation

struct CodexAccountProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var email: String?
    var accountID: String?
    var planType: String?
    var status: CodexAccountStatusSnapshot?
    var statusError: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        email: String? = nil,
        accountID: String? = nil,
        planType: String? = nil,
        status: CodexAccountStatusSnapshot? = nil,
        statusError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountID = accountID
        self.planType = planType
        self.status = status
        self.statusError = statusError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func validate() throws {
        guard !title.isEmpty else {
            throw CodexAccountError.invalidTitle
        }
    }
}

enum CodexAccountError: LocalizedError, Equatable {
    case accountNotFound
    case authCacheMissing
    case authCacheNotSaved
    case invalidAuthCache
    case invalidTitle
    case invalidEmail
    case storageFailure(String)
    case unsafeAuthCachePath
    case applicationCloseFailed
    case applicationLaunchFailed
    case oauthCallbackUnavailable
    case oauthSessionExpired
    case oauthCancelled
    case oauthAuthorizationFailed(String)
    case oauthTokenExchangeFailed
    case oauthInvalidResponse
    case oauthAccountMismatch(expected: String, actual: String)
    case credentialRefreshDeferred
    case credentialRefreshFailed(String)
    case accountStatusUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return "没有找到这个 Codex 账号。"
        case .authCacheMissing:
            return "没有检测到 Codex 登录凭据。请先在 Codex 桌面 App 中通过官方网页完成登录。"
        case .authCacheNotSaved:
            return "当前登录账号尚未保存。请先保存当前账号，再切换到其他账号。"
        case .invalidAuthCache:
            return "Codex 登录凭据格式无效，未执行保存或切换。"
        case .invalidTitle:
            return "账号名称不能为空。"
        case .invalidEmail:
            return "请输入有效的 OpenAI 账号邮箱。"
        case .storageFailure(let message):
            return "无法访问 OneBoard 数据库：\(message)"
        case .unsafeAuthCachePath:
            return "Codex 登录凭据路径是符号链接，为避免覆盖其他文件，已停止切换。"
        case .applicationCloseFailed:
            return "无法完全退出 Codex，未修改当前登录凭据。请手动退出后重试。"
        case .applicationLaunchFailed:
            return "登录凭据已切换，但无法自动打开 Codex，请手动打开。"
        case .oauthCallbackUnavailable:
            return "无法启动 Codex 授权回调，请检查本机网络权限后重试。"
        case .oauthSessionExpired:
            return "Codex 授权会话已失效，请重新发起授权。"
        case .oauthCancelled:
            return "已取消 Codex 授权。"
        case .oauthAuthorizationFailed(let reason):
            return "Codex 授权失败：\(reason)"
        case .oauthTokenExchangeFailed:
            return "Codex 授权已返回，但交换登录凭据失败，请重试。"
        case .oauthInvalidResponse:
            return "Codex 授权返回的账号信息不完整，未保存账号。"
        case .oauthAccountMismatch(let expected, let actual):
            return "浏览器授权的账号是 \(actual)，与填写的 \(expected) 不一致，未保存。"
        case .credentialRefreshDeferred:
            return "当前凭据需要续期；为避免与正在运行的 Codex 重复使用 refresh token，请退出 Codex 后刷新。"
        case .credentialRefreshFailed(let reason):
            return "Codex 登录凭据自动续期失败：\(reason)"
        case .accountStatusUnavailable(let reason):
            return "暂时无法读取 Codex 额度：\(reason)"
        }
    }
}

struct CodexUsageWindowSnapshot: Codable, Equatable, Sendable {
    let remainingPercent: Int
    let resetAt: Date?
    let windowMinutes: Int?
}

struct CodexAccountStatusSnapshot: Codable, Equatable, Sendable {
    let fiveHour: CodexUsageWindowSnapshot?
    let weekly: CodexUsageWindowSnapshot?
    let resetCreditsAvailable: Int?
    let subscriptionActiveUntil: Date?
    let fetchedAt: Date
}

enum CodexAccountSwitchOutcome: Equatable {
    case alreadyActive
    case switched
}
