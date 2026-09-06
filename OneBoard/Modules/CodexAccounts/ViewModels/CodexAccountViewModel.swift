import Foundation

@MainActor
final class CodexAccountViewModel: ObservableObject {
    static let shared = CodexAccountViewModel(startsAutomaticStatusRefresh: true)

    @Published private(set) var profiles: [CodexAccountProfile] = []
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var pendingAccountID: UUID?
    @Published private(set) var isCodexRunning = false
    @Published private(set) var hasCurrentAuthCache = false
    @Published private(set) var isSwitching = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var refreshingAccountIDs: Set<UUID> = []
    @Published private(set) var authorizationURL: URL?
    @Published var statusMessage: String?

    private let service: CodexAccountService
    private let oauthAuthorizer: CodexOAuthAuthorizing
    private let browserOpener: CodexOAuthBrowserOpening
    private var statusRefreshTask: Task<Void, Never>?

    init(
        service: CodexAccountService? = nil,
        oauthAuthorizer: CodexOAuthAuthorizing? = nil,
        browserOpener: CodexOAuthBrowserOpening? = nil,
        startsAutomaticStatusRefresh: Bool = false
    ) {
        self.service = service ?? CodexAccountService()
        self.oauthAuthorizer = oauthAuthorizer ?? SystemCodexOAuthAuthorizer()
        self.browserOpener = browserOpener ?? SystemCodexOAuthBrowserOpener()
        refreshState()
        if startsAutomaticStatusRefresh {
            statusRefreshTask = Task { [weak self] in
                await self?.runAccountStatusRefreshLoop()
            }
        }
    }

    var activeProfile: CodexAccountProfile? {
        profiles.first { $0.id == activeAccountID }
    }

    var pendingProfile: CodexAccountProfile? {
        profiles.first { $0.id == pendingAccountID }
    }

    @discardableResult
    func authorizeAccount(email: String) async -> Bool {
        guard !isAuthorizing else { return false }
        let requestedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requestedEmail.contains("@") else {
            statusMessage = CodexAccountError.invalidEmail.localizedDescription
            return false
        }

        isAuthorizing = true
        authorizationURL = nil
        statusMessage = "正在准备 Codex 官方授权页…"
        defer { isAuthorizing = false }
        do {
            let oauthSession = try await oauthAuthorizer.beginAuthorization()
            authorizationURL = oauthSession.authorizationURL
            statusMessage = "请在浏览器中完成 Codex 授权"
            guard browserOpener.open(oauthSession.authorizationURL) else {
                throw CodexAccountError.oauthAuthorizationFailed("无法打开默认浏览器")
            }
            let credential = try await oauthAuthorizer.waitForAuthorization(session: oauthSession)
            let profile = try service.saveAuthorizedAccount(
                requestedEmail: requestedEmail,
                credential: credential
            )
            authorizationURL = nil
            statusMessage = "已授权并保存 \(profile.title)"
            refreshState()
            return true
        } catch {
            oauthAuthorizer.cancel()
            statusMessage = error.localizedDescription
            return false
        }
    }

    func cancelAuthorization() {
        oauthAuthorizer.cancel()
        authorizationURL = nil
        isAuthorizing = false
        statusMessage = "已取消 Codex 授权"
    }

    func updateProfile(id: UUID, title: String) {
        do {
            try service.updateProfile(id: id, title: title)
            statusMessage = "账号名称已更新"
            refreshState()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshActiveAuthCache() {
        do {
            try service.refreshActiveAuthCache()
            statusMessage = "已更新当前账号的登录凭据"
            refreshState()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshAllAccountStatuses() async {
        guard refreshingAccountIDs.isEmpty else { return }
        for profile in profiles {
            guard !Task.isCancelled else { return }
            refreshingAccountIDs.insert(profile.id)
            do {
                _ = try await service.refreshAccountStatus(id: profile.id)
            } catch {
                // 单账号失败保留在账号行，不能阻断其他账号刷新。
            }
            refreshingAccountIDs.remove(profile.id)
            refreshState()
        }
    }

    func runAccountStatusRefreshLoop() async {
        while !Task.isCancelled {
            await refreshAllAccountStatuses()
            try? await Task.sleep(for: .seconds(900))
        }
    }

    deinit {
        statusRefreshTask?.cancel()
    }

    func deleteAccount(id: UUID) {
        do {
            try service.deleteAccount(id: id)
            statusMessage = "账号及其数据库凭据已删除"
            refreshState()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reorderAccounts(_ ids: [UUID]) {
        service.reorderAccounts(ids)
        refreshState()
    }

    func moveAccount(_ sourceID: UUID, before targetID: UUID) {
        service.moveAccount(sourceID, before: targetID)
        refreshState()
    }

    @discardableResult
    func requestSwitch(id: UUID) async -> String {
        guard !isSwitching else { return statusMessage ?? "Codex 账号正在切换" }
        isSwitching = true
        pendingAccountID = id
        statusMessage = "正在退出 Codex 并切换账号…"
        do {
            let outcome = try await service.requestSwitch(to: id)
            apply(outcome)
            refreshState()
        } catch {
            statusMessage = error.localizedDescription
            refreshState()
        }
        isSwitching = false
        return statusMessage ?? "Codex 账号状态已更新"
    }

    func refreshState() {
        profiles = service.profiles
        activeAccountID = service.activeAccountID
        pendingAccountID = service.pendingAccountID
        isCodexRunning = service.isCodexRunning
        hasCurrentAuthCache = service.hasCurrentAuthCache
    }

    private func apply(_ outcome: CodexAccountSwitchOutcome) {
        switch outcome {
        case .alreadyActive:
            statusMessage = "已经是当前账号"
        case .switched:
            statusMessage = "账号已切换，Codex 已重新打开"
        }
    }
}
