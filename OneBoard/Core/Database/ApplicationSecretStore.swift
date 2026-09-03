import Foundation

final class ApplicationSecretStore: @unchecked Sendable {
    static let shared = ApplicationSecretStore()

    private let repository: PrivateDataRepository
    private let legacyDefaults: UserDefaults
    private let namespace = "application_secret"

    init(repository: PrivateDataRepository = .shared, legacyDefaults: UserDefaults = .standard) {
        self.repository = repository
        self.legacyDefaults = legacyDefaults
    }

    func value(for key: String) -> String {
        if let data = try? repository.load(namespace: namespace, recordID: key),
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        guard let legacy = legacyDefaults.string(forKey: key), !legacy.isEmpty else { return "" }
        if (try? repository.save(Data(legacy.utf8), namespace: namespace, recordID: key)) != nil {
            legacyDefaults.removeObject(forKey: key)
        }
        return legacy
    }

    func setValue(_ value: String, for key: String) {
        do {
            if value.isEmpty {
                try repository.delete(namespace: namespace, recordID: key)
            } else {
                try repository.save(Data(value.utf8), namespace: namespace, recordID: key)
            }
            legacyDefaults.removeObject(forKey: key)
        } catch {
            return
        }
    }
}
