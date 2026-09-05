import Foundation

@MainActor
final class AIUsageViewModel: ObservableObject {
    @Published private(set) var snapshots: [UUID: AIQuotaSnapshot] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var localToday: [UUID: AITokenTotals] = [:]
    @Published private(set) var localTotal: [UUID: AITokenTotals] = [:]
    @Published private(set) var isRefreshing = false
    private var identities: [UUID: String] = [:]
    private let repository = PrivateDataRepository.shared
    private let vault = SQLiteAIProviderSecretVault()

    func loadLocal(_ profiles: [AIProviderProfile]) {
        for profile in profiles where profile.kind == .custom {
            guard let key = try? vault.load(for: profile.id) else {
                snapshots[profile.id] = nil
                localToday[profile.id] = nil
                localTotal[profile.id] = nil
                continue
            }
            let identity = AIUsageIdentity.make(profile: profile, key: key)
            if identities[profile.id] != identity {
                errors[profile.id] = nil
                identities[profile.id] = identity
            }
            localToday[profile.id] = try? AIUsageStore.shared.totals(credentialID: identity, day: Date())
            localTotal[profile.id] = try? AIUsageStore.shared.totals(credentialID: identity)
            if let data = try? repository.load(namespace: "ai_quota", recordID: identity),
               let snapshot = try? JSONDecoder().decode(AIQuotaSnapshot.self, from: data) {
                snapshots[profile.id] = snapshot
            } else { snapshots[profile.id] = nil }
        }
    }

    func refresh(_ profiles: [AIProviderProfile]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        loadLocal(profiles)
        // 相同源、相同 Key 的 Codex/Claude 配置复用同一查询结果。
        var fetched: [String: AIQuotaSnapshot] = [:]
        for profile in profiles where profile.kind == .custom {
            do {
                let key = try vault.load(for: profile.id)
                let identity = AIUsageIdentity.make(profile: profile, key: key)
                let snapshot: AIQuotaSnapshot
                if let cached = fetched[identity] { snapshot = cached }
                else {
                    snapshot = try await AIProviderUsageService().query(profile: profile, key: key)
                    fetched[identity] = snapshot
                    try repository.save(JSONEncoder().encode(snapshot), namespace: "ai_quota", recordID: identity)
                }
                // 编辑或删除期间的旧结果不回填。
                guard AIProviderStore.shared.profiles.first(where: { $0.id == profile.id }) == profile,
                      (try? vault.load(for: profile.id)) == key else { continue }
                snapshots[profile.id] = snapshot
                errors[profile.id] = nil
            } catch {
                guard AIProviderStore.shared.profiles.first(where: { $0.id == profile.id }) == profile else { continue }
                errors[profile.id] = error.localizedDescription
            }
        }
    }
}
