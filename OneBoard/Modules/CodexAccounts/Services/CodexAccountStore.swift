import Foundation

final class CodexAccountStore: @unchecked Sendable {
    static let shared = CodexAccountStore()

    private let defaults: UserDefaults
    private let profilesKey: String
    private let activeIDKey: String
    private let pendingIDKey: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        profilesKey: String = Constants.UserDefaultsKeys.codexAccountProfiles,
        activeIDKey: String = Constants.UserDefaultsKeys.activeCodexAccountID,
        pendingIDKey: String = Constants.UserDefaultsKeys.pendingCodexAccountID
    ) {
        self.defaults = defaults
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
        guard let data = defaults.data(forKey: profilesKey) else { return [] }
        return (try? JSONDecoder().decode([CodexAccountProfile].self, from: data)) ?? []
    }

    private func saveProfiles(_ profiles: [CodexAccountProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: profilesKey)
    }

    private func loadID(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func saveID(_ id: UUID?, forKey key: String) {
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
