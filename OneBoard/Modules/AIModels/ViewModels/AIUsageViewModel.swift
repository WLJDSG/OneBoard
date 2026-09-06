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
            let quotaIdentity = AIUsageIdentity.quota(profile: profile, key: key)
            if identities[profile.id] != quotaIdentity {
                errors[profile.id] = nil
                identities[profile.id] = quotaIdentity
            }
            localToday[profile.id] = try? AIUsageStore.shared.totals(credentialID: identity, day: Date())
            localTotal[profile.id] = try? AIUsageStore.shared.totals(credentialID: identity)
            if profile.quotaAPI != AIQuotaAPI.none,
               let data = try? repository.load(namespace: "ai_quota", recordID: quotaIdentity),
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
        // 相同源、Key 和额度接口的配置复用查询；手动切换额度地址不得沿用旧快照。
        var fetched: [String: AIQuotaSnapshot] = [:]
        for profile in profiles where profile.kind == .custom {
            do {
                let key = try vault.load(for: profile.id)
                guard profile.quotaAPI != AIQuotaAPI.none else { errors[profile.id] = nil; continue }
                let identity = AIUsageIdentity.quota(profile: profile, key: key)
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
