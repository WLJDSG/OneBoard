import Foundation

protocol CodexAuthCacheVaulting {
    func save(_ data: Data, for accountID: UUID) throws
    func load(for accountID: UUID) throws -> Data
    func delete(for accountID: UUID) throws
}

struct SQLiteCodexAuthCacheVault: CodexAuthCacheVaulting {
    private let repository: PrivateDataRepository
    private let namespace = "codex_account_auth_cache"

    init(repository: PrivateDataRepository = .shared) {
        self.repository = repository
    }

    func save(_ data: Data, for accountID: UUID) throws {
        try repository.save(data, namespace: namespace, recordID: accountID.uuidString)
    }

    func load(for accountID: UUID) throws -> Data {
        guard let data = try repository.load(namespace: namespace, recordID: accountID.uuidString) else {
            throw CodexAccountError.authCacheMissing
        }
        return data
    }

    func delete(for accountID: UUID) throws {
        try repository.delete(namespace: namespace, recordID: accountID.uuidString)
    }
}
