import Foundation

protocol AIProviderSecretVaulting {
    func save(_ secret: String, for profileID: UUID) throws
    func load(for profileID: UUID) throws -> String
    func contains(profileID: UUID) -> Bool
    func delete(for profileID: UUID) throws
}

struct SQLiteAIProviderSecretVault: AIProviderSecretVaulting {
    private let repository: PrivateDataRepository
    private let namespace = "ai_provider_api_key"

    init(repository: PrivateDataRepository = .shared) {
        self.repository = repository
    }

    func save(_ secret: String, for profileID: UUID) throws {
        try repository.save(Data(secret.utf8), namespace: namespace, recordID: profileID.uuidString)
    }

    func load(for profileID: UUID) throws -> String {
        guard let data = try repository.load(namespace: namespace, recordID: profileID.uuidString),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw AIModelSwitchError.apiKeyMissing
        }
        return value
    }

    func contains(profileID: UUID) -> Bool {
        repository.contains(namespace: namespace, recordID: profileID.uuidString)
    }

    func delete(for profileID: UUID) throws {
        try repository.delete(namespace: namespace, recordID: profileID.uuidString)
    }
}
