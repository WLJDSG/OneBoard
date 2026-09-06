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
            return AIProviderQuotaPresentation(text: "额度：暂未接入此供应商查询", tone: .unavailable)
        }
        guard let account = activeCodexAccount else {
            return AIProviderQuotaPresentation(text: "额度：尚未关联 Codex 账号", tone: .unavailable)
        }
        if let status = account.status {
            var parts: [String] = []
            if let plan = account.planType, !plan.isEmpty { parts.append(plan.uppercased()) }
            if let window = status.fiveHour { parts.append("5 小时 \(window.remainingPercent)%") }
            if let window = status.weekly { parts.append("每周 \(window.remainingPercent)%") }
            parts.append(account.title)
            return AIProviderQuotaPresentation(
                text: "额度：" + parts.joined(separator: " · "),
                tone: .normal
            )
        }
        if account.statusError != nil {
            return AIProviderQuotaPresentation(text: "额度：读取失败，请在 Codex 账号页刷新", tone: .warning)
        }
        return AIProviderQuotaPresentation(text: "额度：尚未同步，请在 Codex 账号页刷新", tone: .unavailable)
    }
}
