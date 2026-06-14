import Foundation

final class GatewayProfileStore: @unchecked Sendable {
    static let shared = GatewayProfileStore()

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        key: String = Constants.UserDefaultsKeys.gatewayProfiles
    ) {
        self.defaults = defaults
        self.key = key
    }

    var profiles: [GatewayProfile] {
        get { lock.withLock { load() } }
        set { lock.withLock { save(newValue) } }
    }

    func initializeDefaultsIfNeeded() -> [GatewayProfile] {
        lock.lock()
        defer { lock.unlock() }
        if defaults.object(forKey: key) == nil {
            save(GatewayProfile.defaults)
        }
        return load()
    }

    func add(_ profile: GatewayProfile) {
        lock.lock()
        defer { lock.unlock() }
        var current = load()
        current.append(profile)
        save(current)
    }

    func update(_ profile: GatewayProfile) {
        lock.lock()
        defer { lock.unlock() }
        var current = load()
        if let index = current.firstIndex(where: { $0.id == profile.id }) {
            current[index] = profile
        }
        save(current)
    }

    func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var current = load()
        current.removeAll { $0.id == id }
        save(current)
    }

    private func load() -> [GatewayProfile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GatewayProfile].self, from: data)) ?? []
    }

    private func save(_ profiles: [GatewayProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
