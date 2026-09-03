import Foundation

final class AIProviderStore: @unchecked Sendable {
    static let shared = AIProviderStore(repository: .shared)

    private let defaults: UserDefaults?
    private let legacyDefaults: UserDefaults
    private let repository: PrivateDataRepository?
    private let profilesKey: String
    private let activeCodexKey: String
    private let activeClaudeKey: String
    private let lock = NSLock()

    init(repository: PrivateDataRepository, legacyDefaults: UserDefaults = .standard) {
        self.repository = repository
        self.legacyDefaults = legacyDefaults
        defaults = nil
        profilesKey = Constants.UserDefaultsKeys.aiProviderProfiles
        activeCodexKey = Constants.UserDefaultsKeys.activeCodexProviderID
        activeClaudeKey = Constants.UserDefaultsKeys.activeClaudeProviderID
    }

    init(
        defaults: UserDefaults = .standard,
        profilesKey: String = Constants.UserDefaultsKeys.aiProviderProfiles,
        activeCodexKey: String = Constants.UserDefaultsKeys.activeCodexProviderID,
        activeClaudeKey: String = Constants.UserDefaultsKeys.activeClaudeProviderID
    ) {
        self.defaults = defaults
        legacyDefaults = defaults
        repository = nil
        self.profilesKey = profilesKey
        self.activeCodexKey = activeCodexKey
        self.activeClaudeKey = activeClaudeKey
    }

    var profiles: [AIProviderProfile] {
        get { lock.withLock { loadProfiles() } }
        set { lock.withLock { saveProfiles(newValue) } }
    }

    func activeID(for client: AIClient) -> UUID? {
        lock.withLock {
            migrateLegacyIfNeeded()
            let key = activeKey(for: client)
            if let data = repository.flatMap({ try? $0.loadState(key: key) }),
               let value = String(data: data, encoding: .utf8) {
                return UUID(uuidString: value)
            }
            return defaults?.string(forKey: key).flatMap(UUID.init(uuidString:))
        }
    }

    func setActiveID(_ id: UUID?, for client: AIClient) {
        lock.withLock {
            let key = activeKey(for: client)
            if let repository {
                if let id { try? repository.saveState(Data(id.uuidString.utf8), key: key) }
                else { try? repository.deleteState(key: key) }
            } else if let id { defaults?.set(id.uuidString, forKey: key) }
            else { defaults?.removeObject(forKey: key) }
        }
    }

    func save(_ profile: AIProviderProfile) {
        lock.withLock {
            var current = loadProfiles()
            if let index = current.firstIndex(where: { $0.id == profile.id }) {
                current[index] = profile
            } else {
                current.append(profile)
            }
            saveProfiles(current)
        }
    }

    func delete(id: UUID) {
        lock.withLock {
            var current = loadProfiles()
            let deletedClient = current.first(where: { $0.id == id })?.client
            current.removeAll { $0.id == id }
            saveProfiles(current)
            if let deletedClient,
               activeIDWithoutLock(for: deletedClient) == id {
                let key = activeKey(for: deletedClient)
                if let repository { try? repository.deleteState(key: key) }
                else { defaults?.removeObject(forKey: key) }
            }
        }
    }

    private func activeKey(for client: AIClient) -> String {
        client == .codex ? activeCodexKey : activeClaudeKey
    }

    private func loadProfiles() -> [AIProviderProfile] {
        migrateLegacyIfNeeded()
        let data = repository.flatMap { try? $0.loadState(key: profilesKey) }
            ?? defaults?.data(forKey: profilesKey)
        guard let data else { return [] }
        return (try? JSONDecoder().decode([AIProviderProfile].self, from: data)) ?? []
    }

    private func saveProfiles(_ profiles: [AIProviderProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        if let repository { try? repository.saveState(data, key: profilesKey) }
        else { defaults?.set(data, forKey: profilesKey) }
    }

    private func activeIDWithoutLock(for client: AIClient) -> UUID? {
        let key = activeKey(for: client)
        if let data = repository.flatMap({ try? $0.loadState(key: key) }),
           let value = String(data: data, encoding: .utf8) {
            return UUID(uuidString: value)
        }
        return defaults?.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func migrateLegacyIfNeeded() {
        guard let repository,
              (try? repository.loadState(key: "ai_provider_store_migrated")) == nil else { return }
        do {
            if let profiles = legacyDefaults.data(forKey: profilesKey) {
                try repository.saveState(profiles, key: profilesKey)
            }
            for key in [activeCodexKey, activeClaudeKey] {
                if let value = legacyDefaults.string(forKey: key) {
                    try repository.saveState(Data(value.utf8), key: key)
                }
            }
            try repository.saveState(Data("1".utf8), key: "ai_provider_store_migrated")
            legacyDefaults.removeObject(forKey: profilesKey)
            legacyDefaults.removeObject(forKey: activeCodexKey)
            legacyDefaults.removeObject(forKey: activeClaudeKey)
        } catch {
            return
        }
    }
}
