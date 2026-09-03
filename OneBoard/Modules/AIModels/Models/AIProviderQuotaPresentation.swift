import Foundation

struct AIProviderQuotaPresentation: Equatable {
    enum Tone: Equatable {
        case normal
        case unavailable
        case warning
    }

    let text: String
    let tone: Tone

    static func make(
        profile: AIProviderProfile,
        activeCodexAccount: CodexAccountProfile?
    ) -> AIProviderQuotaPresentation {
        guard profile.client == .codex, profile.kind == .official else {
            return AIProviderQuotaPresentation(text: "额度：未配置查询", tone: .unavailable)
        }
        guard let account = activeCodexAccount else {
            return AIProviderQuotaPresentation(text: "额度：尚未关联 Codex 账号", tone: .unavailable)
        }
        if let status = account.status {
            let fiveHour = status.fiveHour.map { "\($0.remainingPercent)%" } ?? "--"
            let weekly = status.weekly.map { "\($0.remainingPercent)%" } ?? "--"
            return AIProviderQuotaPresentation(
                text: "额度：5 小时 \(fiveHour) · 每周 \(weekly) · \(account.title)",
                tone: .normal
            )
        }
        if account.statusError != nil {
            return AIProviderQuotaPresentation(text: "额度：读取失败，请在 Codex 账号页刷新", tone: .warning)
        }
        return AIProviderQuotaPresentation(text: "额度：尚未同步，请在 Codex 账号页刷新", tone: .unavailable)
    }
}
