import Foundation
import Security

protocol CodexAuthCacheVaulting {
    func save(_ data: Data, for accountID: UUID) throws
    func load(for accountID: UUID) throws -> Data
    func delete(for accountID: UUID) throws
}

struct KeychainCodexAuthCacheVault: CodexAuthCacheVaulting {
    private let service: String

    init(service: String = Constants.codexAuthCacheKeychainService) {
        self.service = service
    }

    func save(_ data: Data, for accountID: UUID) throws {
        let query = baseQuery(for: accountID)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw keychainError(updateStatus) }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
    }

    func load(for accountID: UUID) throws -> Data {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { throw CodexAccountError.authCacheMissing }
            throw keychainError(status)
        }
        return data
    }

    func delete(for accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }

    private func keychainError(_ status: OSStatus) -> CodexAccountError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "错误码 \(status)"
        return .keychainFailure(message)
    }
}
