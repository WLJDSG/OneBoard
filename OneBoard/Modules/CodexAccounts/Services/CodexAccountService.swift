import Foundation

@MainActor
final class CodexAccountService {
    private let store: CodexAccountStore
    private let vault: CodexAuthCacheVaulting
    private let authCacheFile: CodexAuthCacheFileHandling
    private let applicationLifecycle: CodexApplicationLifecycleControlling
    private let statusProvider: CodexAccountStatusProviding
    private let now: () -> Date

    init(
        store: CodexAccountStore = .shared,
        vault: CodexAuthCacheVaulting = SQLiteCodexAuthCacheVault(),
        authCacheFile: CodexAuthCacheFileHandling = CodexAuthCredentialStore(),
        applicationLifecycle: CodexApplicationLifecycleControlling? = nil,
        statusProvider: CodexAccountStatusProviding = CodexAccountStatusService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.vault = vault
        self.authCacheFile = authCacheFile
        self.applicationLifecycle = applicationLifecycle ?? SystemCodexApplicationLifecycleController()
        self.statusProvider = statusProvider
        self.now = now
        // 旧版本可能留下“等待手动退出”状态；新流程不在跨启动间恢复进程操作。
        store.pendingAccountID = nil
    }

    var profiles: [CodexAccountProfile] { store.profiles }
    var activeAccountID: UUID? { store.activeAccountID }
    var pendingAccountID: UUID? { store.pendingAccountID }
    var isCodexRunning: Bool { applicationLifecycle.isRunning }
    var hasCurrentAuthCache: Bool { authCacheFile.exists }

    func moveAccount(_ sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID else { return }
        var ordered = profiles
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let item = ordered.remove(at: sourceIndex)
        guard let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        ordered.insert(item, at: targetIndex)
        store.profiles = ordered
    }

    @discardableResult
    func saveAuthorizedAccount(requestedEmail: String, credential: CodexOAuthCredential) throws -> CodexAccountProfile {
        let expected = requestedEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expected.contains("@") else { throw CodexAccountError.invalidEmail }
        let actual = credential.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expected == actual else {
            throw CodexAccountError.oauthAccountMismatch(expected: expected, actual: actual)
        }

        if var existing = profiles.first(where: { $0.email?.lowercased() == actual }) {
            try vault.save(credential.authCache, for: existing.id)
            existing.accountID = credential.accountID
            existing.planType = credential.planType
            existing.updatedAt = now()
            store.update(existing)
            return existing
        }

        var profile = CodexAccountProfile(
            title: credential.email,
            email: credential.email,
            accountID: credential.accountID,
            planType: credential.planType,
            createdAt: now(),
            updatedAt: now()
        )
        try profile.validate()
        try vault.save(credential.authCache, for: profile.id)
        profile.updatedAt = now()
        store.add(profile)
        return profile
    }

    func updateProfile(id: UUID, title: String) throws {
        guard var profile = profiles.first(where: { $0.id == id }) else {
            throw CodexAccountError.accountNotFound
        }
        profile.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try profile.validate()
        profile.updatedAt = now()
        store.update(profile)
    }

    func refreshActiveAuthCache() throws {
        guard let activeID = activeAccountID,
              var profile = profiles.first(where: { $0.id == activeID }) else {
            throw CodexAccountError.authCacheNotSaved
        }
        let data = try authCacheFile.read()
        try vault.save(data, for: activeID)
        profile.updatedAt = now()
        store.update(profile)
    }

    @discardableResult
    func refreshAccountStatus(id: UUID) async throws -> CodexAccountProfile {
        guard var profile = profiles.first(where: { $0.id == id }) else {
            throw CodexAccountError.accountNotFound
        }
        let savedData = try vault.load(for: id)
        var data = savedData
        // 当前账号以 Codex auth.json 为最新权威；读取后同步回 OneBoard SQLite，
        // 这样 Codex 自己完成过 token 轮换时不会继续使用旧 refresh token。
        if activeAccountID == id, authCacheFile.exists {
            let currentData = try authCacheFile.read()
            try validateAuthCache(currentData)
            data = currentData
            if currentData != savedData {
                try vault.save(currentData, for: id)
                profile.updatedAt = now()
            }
        }
        let canRefreshCredential = activeAccountID != id || !isCodexRunning

        do {
            let result = try await statusProvider.refreshStatus(
                authCache: data,
                accountID: profile.accountID,
                allowCredentialRefresh: canRefreshCredential
            )
            if let refreshed = result.refreshedAuthCache {
                try vault.save(refreshed, for: id)
                if activeAccountID == id {
                    try authCacheFile.replace(with: refreshed)
                }
                profile.updatedAt = now()
            }
            profile.planType = result.planType ?? profile.planType
            profile.status = result.status
            profile.statusError = nil
            store.update(profile)
            return profile
        } catch {
            profile.statusError = error.localizedDescription
            store.update(profile)
            throw error
        }
    }

    func deleteAccount(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw CodexAccountError.accountNotFound
        }
        try vault.delete(for: id)
        store.delete(id: id)
    }

    func requestSwitch(to targetID: UUID) async throws -> CodexAccountSwitchOutcome {
        guard profiles.contains(where: { $0.id == targetID }) else {
            throw CodexAccountError.accountNotFound
        }
        if activeAccountID == targetID {
            store.pendingAccountID = nil
            return .alreadyActive
        }

        // 关闭 Codex 前就加载并校验目标凭据，避免无效请求影响当前会话。
        let storedTargetData = try vault.load(for: targetID)
        try validateAuthCache(storedTargetData)
        // 切换前自动续期目标凭据。此时目标账号尚未交给 Codex，不会与当前账号争用凭据。
        let targetData = try await statusProvider.prepareCredential(storedTargetData)
        try validateAuthCache(targetData)
        if targetData != storedTargetData {
            try vault.save(targetData, for: targetID)
            if var profile = profiles.first(where: { $0.id == targetID }) {
                profile.updatedAt = now()
                store.update(profile)
            }
        }
        store.pendingAccountID = targetID
        do {
            try await applicationLifecycle.closeAndWait()
            guard !isCodexRunning else {
                throw CodexAccountError.applicationCloseFailed
            }
            try performSwitch(to: targetID, targetData: targetData)
        } catch {
            store.pendingAccountID = nil
            throw error
        }
        try await applicationLifecycle.launch()
        return .switched
    }

    private func performSwitch(to targetID: UUID, targetData: Data) throws {
        if let activeID = activeAccountID {
            if authCacheFile.exists {
                let currentData = try authCacheFile.read()
                try vault.save(currentData, for: activeID)
            }
        }

        try authCacheFile.replace(with: targetData)
        store.activeAccountID = targetID
        store.pendingAccountID = nil

        if var profile = profiles.first(where: { $0.id == targetID }) {
            profile.updatedAt = now()
            store.update(profile)
        }
    }

    private func validateAuthCache(_ data: Data) throws {
        guard !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw CodexAccountError.invalidAuthCache
        }
    }
}
