import CryptoKit
import Foundation
import Security

enum CodexAuthCredentialsStoreMode: String, Equatable {
    case file
    case keyring
    case auto
}

protocol CodexAuthStoreModeResolving {
    func resolveMode() -> CodexAuthCredentialsStoreMode
}

struct CodexConfigAuthStoreModeResolver: CodexAuthStoreModeResolving {
    private let configURL: URL

    init(configURL: URL) {
        self.configURL = configURL
    }

    func resolveMode() -> CodexAuthCredentialsStoreMode {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .file
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=") else { continue }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "cli_auth_credentials_store" else { continue }

            let rawValue = line[line.index(after: separator)...]
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
            return CodexAuthCredentialsStoreMode(rawValue: rawValue) ?? .file
        }
        return .file
    }
}

protocol CodexOfficialKeychainHandling {
    func read(account: String) throws -> Data?
    func save(_ data: Data, account: String) throws
}

struct CodexOfficialKeychainStore: CodexOfficialKeychainHandling {
    private let service = "Codex Auth"

    func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        return data
    }

    func save(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw keychainError(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainError(_ status: OSStatus) -> CodexAccountError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "错误码 \(status)"
        return .keychainFailure(message)
    }
}

/// 读写 Codex 官方当前登录存储；OneBoard 自己的多账号快照仍由独立 Keychain vault 管理。
final class CodexAuthCredentialStore: CodexAuthCacheFileHandling {
    private let authFile: CodexAuthCacheFile
    private let modeResolver: CodexAuthStoreModeResolving
    private let officialKeychain: CodexOfficialKeychainHandling
    private let officialKeychainAccount: String

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default,
        modeResolver: CodexAuthStoreModeResolving? = nil,
        officialKeychain: CodexOfficialKeychainHandling = CodexOfficialKeychainStore()
    ) {
        let resolvedHome = codexHome.resolvingSymlinksInPath().standardizedFileURL
        authFile = CodexAuthCacheFile(
            url: resolvedHome.appendingPathComponent("auth.json"),
            fileManager: fileManager
        )
        self.modeResolver = modeResolver ?? CodexConfigAuthStoreModeResolver(
            configURL: resolvedHome.appendingPathComponent("config.toml")
        )
        self.officialKeychain = officialKeychain
        officialKeychainAccount = Self.keychainAccount(for: resolvedHome)
    }

    var exists: Bool {
        (try? read()) != nil
    }

    func read() throws -> Data {
        switch modeResolver.resolveMode() {
        case .file:
            return try authFile.read()
        case .keyring, .auto:
            do {
                if let data = try officialKeychain.read(account: officialKeychainAccount) {
                    try validate(data)
                    return data
                }
            } catch {
                guard authFile.exists else { throw error }
            }
            return try authFile.read()
        }
    }

    func replace(with data: Data) throws {
        try validate(data)

        switch modeResolver.resolveMode() {
        case .file:
            try authFile.replace(with: data)
        case .keyring:
            try officialKeychain.save(data, account: officialKeychainAccount)
            try? authFile.removeIfPresent()
        case .auto:
            do {
                try officialKeychain.save(data, account: officialKeychainAccount)
                try? authFile.removeIfPresent()
            } catch {
                try authFile.replace(with: data)
            }
        }
    }

    static func keychainAccount(for codexHome: URL) -> String {
        let path = codexHome.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let prefix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "cli|\(prefix)"
    }

    private func validate(_ data: Data) throws {
        guard !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw CodexAccountError.invalidAuthCache
        }
    }
}
