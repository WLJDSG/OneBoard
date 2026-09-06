import Foundation

@MainActor
final class AIModelSwitcherViewModel: ObservableObject {
    static let shared = AIModelSwitcherViewModel()

    @Published private(set) var profiles: [AIProviderProfile] = []
    @Published private(set) var isSwitching = false
    @Published var statusMessage: String?

    private var officialCredentialRefreshTask: Task<Void, Never>?
    private let store: AIProviderStore
    private let vault: AIProviderSecretVaulting
    private let writer: AIModelConfigurationWriting
    private let proxyCoordinator: AIProxyCoordinating
    private let applicationLifecycle: CodexApplicationLifecycleControlling
    private let ccSwitchImporter: CCSwitchProviderImporter

    init(
        store: AIProviderStore = .shared,
        vault: AIProviderSecretVaulting = SQLiteAIProviderSecretVault(),
        writer: AIModelConfigurationWriting = AIModelConfigurationWriter(),
        proxyCoordinator: AIProxyCoordinating = AIProxyCoordinator.shared,
        applicationLifecycle: CodexApplicationLifecycleControlling? = nil,
        ccSwitchImporter: CCSwitchProviderImporter = CCSwitchProviderImporter()
    ) {
        self.store = store
        self.vault = vault
        self.writer = writer
        self.proxyCoordinator = proxyCoordinator
        self.applicationLifecycle = applicationLifecycle ?? SystemCodexApplicationLifecycleController()
        self.ccSwitchImporter = ccSwitchImporter
        reload()
    }

    deinit { officialCredentialRefreshTask?.cancel() }

    func profiles(for client: AIClient) -> [AIProviderProfile] {
        profiles.filter { $0.client == client }
    }

    func activeID(for client: AIClient) -> UUID? {
        store.activeID(for: client)
    }

    func hasSavedAPIKey(for profile: AIProviderProfile) -> Bool {
        vault.contains(profileID: profile.id)
    }

    func savedAPIKey(for profile: AIProviderProfile) -> String? {
        guard profile.kind == .custom else { return nil }
        return try? vault.load(for: profile.id)
    }

    func save(_ profile: AIProviderProfile, apiKey: String?) async throws {
        let wasActive = store.activeID(for: profile.client) == profile.id
        var validated = try profile.validated()
        validated.updatedAt = Date()
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if validated.kind == .custom {
            guard !trimmedKey.isEmpty || vault.contains(profileID: validated.id) else {
                throw AIModelSwitchError.apiKeyMissing
            }
            if !trimmedKey.isEmpty { try vault.save(trimmedKey, for: validated.id) }
        } else {
            try vault.delete(for: validated.id)
        }
        store.save(validated)
        reload()
        if wasActive {
            _ = await switchProfile(id: validated.id)
        } else {
            statusMessage = "已保存 \(validated.title)"
        }
    }

    func saveAndSwitch(_ profile: AIProviderProfile, apiKey: String?) async throws {
        try await save(profile, apiKey: apiKey)
        guard store.activeID(for: profile.client) != profile.id else { return }
        let message = await switchProfile(id: profile.id)
        guard store.activeID(for: profile.client) == profile.id else {
            throw AIModelSwitchError.activationFailed(message)
        }
    }

    func delete(_ profile: AIProviderProfile) {
        do {
            try vault.delete(for: profile.id)
            if profile.client == .claude, let id = profile.officialAccountID { try ClaudeAccountCredentialStore().delete(id: id) }
            store.delete(id: profile.id)
            reload()
            statusMessage = "已删除 \(profile.title)；当前活动配置文件未改动"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reorderProfiles(_ ids: [UUID], client: AIClient) {
        let current = profiles.filter { $0.client == client }
        guard ids.count == current.count, Set(ids) == Set(current.map(\.id)) else { return }
        var remaining = ids.compactMap { id in current.first { $0.id == id } }.makeIterator()
        store.profiles = profiles.map { $0.client == client ? remaining.next()! : $0 }
        reload()
    }

    func moveProfile(_ sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let source = profiles.first(where: { $0.id == sourceID }),
              source.client == profiles.first(where: { $0.id == targetID })?.client else { return }
        var ordered = profiles
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let item = ordered.remove(at: sourceIndex)
        guard let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        ordered.insert(item, at: targetIndex)
        store.profiles = ordered
        reload()
    }

    @discardableResult
    func switchProfile(id: UUID) async -> String {
        guard !isSwitching else { return "正在切换，请稍后重试" }
        guard let profile = profiles.first(where: { $0.id == id }) else {
            let message = AIModelSwitchError.profileNotFound.localizedDescription
            statusMessage = message
            return message
        }
        isSwitching = true
        defer { isSwitching = false }
        let previousActiveIDs = Dictionary(uniqueKeysWithValues: AIClient.allCases.compactMap { client in
            store.activeID(for: client).map { (client, $0) }
        })
        let codexWasRunning = profile.client == .codex && applicationLifecycle.isRunning
        do {
            var apiKey = profile.kind == .custom ? try vault.load(for: profile.id) : nil
            if profile.kind == .official, let accountID = profile.officialAccountID {
                if profile.client == .codex {
                    let accounts = CodexAccountViewModel.shared
                    if accounts.activeAccountID != accountID {
                        let message = await accounts.requestSwitch(id: accountID)
                        guard accounts.activeAccountID == accountID else { throw AIModelSwitchError.activationFailed(message) }
                    }
                } else {
                    let store = ClaudeAccountCredentialStore()
                    guard let saved = try store.load(id: accountID) else { throw AIProviderQuotaError("请重新登录 Claude Code 官方账号") }
                    let fresh = try await ClaudeAccountAuthorization().refreshed(saved)
                    try store.save(fresh, id: accountID)
                    apiKey = fresh.accessToken
                }
            }
            let routing: AIProxyRouting?
            if profile.kind == .custom, let apiKey {
                routing = try proxyCoordinator.prepare(
                    switching: profile,
                    apiKey: apiKey,
                    profiles: profiles,
                    activeIDs: previousActiveIDs,
                    secretLoader: { try self.vault.load(for: $0) }
                )
            } else {
                routing = nil
            }
            if codexWasRunning {
                try await applicationLifecycle.closeAndWait()
                guard !applicationLifecycle.isRunning else {
                    throw CodexAccountError.applicationCloseFailed
                }
            }
            try writer.apply(profile, apiKey: apiKey, routing: routing)
            store.setActiveID(profile.id, for: profile.client)
            if codexWasRunning {
                do {
                    try await applicationLifecycle.launch()
                } catch {
                    let message = "已切换 Codex 到 \(profile.title) / \(profile.model)，但 Codex 重新打开失败，请手动打开"
                    statusMessage = message
                    return message
                }
            }
            let suffix: String
            if profile.client == .codex {
                suffix = codexWasRunning ? "；Codex 已重新打开" : "；下次启动 Codex 时生效"
            } else {
                suffix = "；新会话生效"
            }
            let message = "已切换 \(profile.client.title) 到 \(profile.title) / \(profile.model)\(suffix)"
            statusMessage = message
            return message
        } catch {
            try? proxyCoordinator.restore(
                profiles: profiles,
                activeIDs: previousActiveIDs,
                secretLoader: { try self.vault.load(for: $0) }
            )
            if codexWasRunning, !applicationLifecycle.isRunning {
                try? await applicationLifecycle.launch()
            }
            let message = error.localizedDescription
            statusMessage = message
            return message
        }
    }

    func restoreBackup(for client: AIClient) {
        do {
            try writer.restoreBackup(for: client)
            store.setActiveID(nil, for: client)
            statusMessage = "已恢复 \(client.title) 的 OneBoard 初次切换前备份"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resumeProxyIfNeeded() {
        startOfficialCredentialRefresh()
        let activeProfiles = AIClient.allCases.compactMap { client -> AIProviderProfile? in
            guard let id = store.activeID(for: client) else { return nil }
            return profiles.first { $0.id == id && $0.kind == .custom }
        }
        guard let first = activeProfiles.first else { return }
        do {
            let firstKey = try vault.load(for: first.id)
            let activeIDs = Dictionary(uniqueKeysWithValues: activeProfiles.map { ($0.client, $0.id) })
            let firstRouting = try proxyCoordinator.prepare(
                switching: first,
                apiKey: firstKey,
                profiles: profiles,
                activeIDs: activeIDs,
                secretLoader: { try self.vault.load(for: $0) }
            )
            let proxyRoot = first.client == .codex
                ? String(firstRouting.baseURL.dropLast(3))
                : firstRouting.baseURL
            for profile in activeProfiles {
                let key = profile.id == first.id ? firstKey : try vault.load(for: profile.id)
                let baseURL = profile.client == .codex
                    ? proxyRoot + "/v1"
                    : proxyRoot
                try writer.apply(profile, apiKey: key, routing: AIProxyRouting(baseURL: baseURL))
            }
        } catch {
            statusMessage = "恢复本地代理失败：\(error.localizedDescription)"
        }
    }

    /// 仅续期活动 Claude 账号，新会话读取更新后的官方 OAuth token。
    private func startOfficialCredentialRefresh() {
        guard officialCredentialRefreshTask == nil else { return }
        officialCredentialRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, !self.isSwitching,
                   let activeID = self.store.activeID(for: .claude),
                   let profile = self.profiles.first(where: { $0.id == activeID && $0.kind == .official }),
                   let accountID = profile.officialAccountID,
                   let credential = try? ClaudeAccountCredentialStore().load(id: accountID),
                   credential.expiresAt.timeIntervalSinceNow < 300 {
                    _ = await self.switchProfile(id: profile.id)
                }
                try? await Task.sleep(for: .seconds(240))
            }
        }
    }

    func importFromCCSwitch() {
        do {
            let summary = try OneBoardMaintenance.importCCSwitch(
                store: store,
                vault: vault,
                importer: ccSwitchImporter
            )
            reload()
            let skipped = summary.skippedNames.isEmpty
                ? ""
                : "；跳过缺少必要字段的：\(summary.skippedNames.joined(separator: "、"))"
            statusMessage = "已从 CC Switch 导入 \(summary.importedCount) 个配置\(skipped)。未改动 CC Switch 和当前运行配置"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reload() {
        profiles = store.profiles
    }
}
