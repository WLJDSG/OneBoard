import Foundation

final class CodexAccountStore: @unchecked Sendable {
    static let shared = CodexAccountStore(repository: .shared)

    private let defaults: UserDefaults?
    private let legacyDefaults: UserDefaults
    private let repository: PrivateDataRepository?
    private let profilesKey: String
    private let activeIDKey: String
    private let pendingIDKey: String
    private let lock = NSLock()

    init(repository: PrivateDataRepository, legacyDefaults: UserDefaults = .standard) {
        self.repository = repository
        self.legacyDefaults = legacyDefaults
        defaults = nil
        profilesKey = Constants.UserDefaultsKeys.codexAccountProfiles
        activeIDKey = Constants.UserDefaultsKeys.activeCodexAccountID
        pendingIDKey = Constants.UserDefaultsKeys.pendingCodexAccountID
    }

    init(
        defaults: UserDefaults = .standard,
        profilesKey: String = Constants.UserDefaultsKeys.codexAccountProfiles,
        activeIDKey: String = Constants.UserDefaultsKeys.activeCodexAccountID,
        pendingIDKey: String = Constants.UserDefaultsKeys.pendingCodexAccountID
    ) {
        self.defaults = defaults
        legacyDefaults = defaults
        repository = nil
        self.profilesKey = profilesKey
        self.activeIDKey = activeIDKey
        self.pendingIDKey = pendingIDKey
    }

    var profiles: [CodexAccountProfile] {
        get { lock.withLock { loadProfiles() } }
        set { lock.withLock { saveProfiles(newValue) } }
    }

    var activeAccountID: UUID? {
        get { lock.withLock { loadID(forKey: activeIDKey) } }
        set { lock.withLock { saveID(newValue, forKey: activeIDKey) } }
    }

    var pendingAccountID: UUID? {
        get { lock.withLock { loadID(forKey: pendingIDKey) } }
        set { lock.withLock { saveID(newValue, forKey: pendingIDKey) } }
    }

    func add(_ profile: CodexAccountProfile) {
        lock.withLock {
            var current = loadProfiles()
            current.append(profile)
            saveProfiles(current)
        }
    }

    func update(_ profile: CodexAccountProfile) {
        lock.withLock {
            var current = loadProfiles()
            if let index = current.firstIndex(where: { $0.id == profile.id }) {
                current[index] = profile
                saveProfiles(current)
            }
        }
    }

    func delete(id: UUID) {
        lock.withLock {
            var current = loadProfiles()
            current.removeAll { $0.id == id }
            saveProfiles(current)
            if loadID(forKey: activeIDKey) == id { saveID(nil, forKey: activeIDKey) }
            if loadID(forKey: pendingIDKey) == id { saveID(nil, forKey: pendingIDKey) }
        }
    }

    private func loadProfiles() -> [CodexAccountProfile] {
        migrateLegacyIfNeeded()
        let data = repository.flatMap { try? $0.loadState(key: profilesKey) }
            ?? defaults?.data(forKey: profilesKey)
        guard let data else { return [] }
        return (try? JSONDecoder().decode([CodexAccountProfile].self, from: data)) ?? []
    }

    private func saveProfiles(_ profiles: [CodexAccountProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        if let repository { try? repository.saveState(data, key: profilesKey) }
        else { defaults?.set(data, forKey: profilesKey) }
    }

    private func loadID(forKey key: String) -> UUID? {
        migrateLegacyIfNeeded()
        if let data = repository.flatMap({ try? $0.loadState(key: key) }),
           let value = String(data: data, encoding: .utf8) {
            return UUID(uuidString: value)
        }
        return defaults?.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func saveID(_ id: UUID?, forKey key: String) {
        if let repository {
            if let id { try? repository.saveState(Data(id.uuidString.utf8), key: key) }
            else { try? repository.deleteState(key: key) }
        } else if let id {
            defaults?.set(id.uuidString, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }

    private func migrateLegacyIfNeeded() {
        guard let repository,
              (try? repository.loadState(key: "codex_account_store_migrated")) == nil else { return }
        do {
            if let profiles = legacyDefaults.data(forKey: profilesKey) {
                try repository.saveState(profiles, key: profilesKey)
            }
            for key in [activeIDKey, pendingIDKey] {
                if let value = legacyDefaults.string(forKey: key) {
                    try repository.saveState(Data(value.utf8), key: key)
                }
            }
            try repository.saveState(Data("1".utf8), key: "codex_account_store_migrated")
            legacyDefaults.removeObject(forKey: profilesKey)
            legacyDefaults.removeObject(forKey: activeIDKey)
            legacyDefaults.removeObject(forKey: pendingIDKey)
        } catch {
            return
        }
    }
}
