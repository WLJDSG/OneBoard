import Foundation
import XCTest
@testable import OneBoardKit

final class CodexAuthCredentialStoreTests: XCTestCase {
    func testConfigResolverReadsOnlyTopLevelOfficialMode() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        try Data("cli_auth_credentials_store = \"keyring\"\n[other]\ncli_auth_credentials_store = \"file\"\n".utf8)
            .write(to: configURL)

        XCTAssertEqual(CodexConfigAuthStoreModeResolver(configURL: configURL).resolveMode(), .keyring)
    }

    func testKeyringModeReadsOfficialKeychainCredential() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = FakeOfficialKeychain()
        keychain.data = authData("keyring")
        let store = makeStore(home: directory, mode: .keyring, keychain: keychain)

        XCTAssertEqual(try store.read(), authData("keyring"))
        XCTAssertTrue(keychain.lastAccount?.hasPrefix("cli|") == true)
        XCTAssertEqual(keychain.lastAccount?.count, 20)
    }

    func testKeyringModeWritesKeychainAndRemovesFileFallback() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let authURL = directory.appendingPathComponent("auth.json")
        try authData("old-file").write(to: authURL)
        let keychain = FakeOfficialKeychain()
        let store = makeStore(home: directory, mode: .keyring, keychain: keychain)

        try store.replace(with: authData("new-keyring"))

        XCTAssertEqual(keychain.data, authData("new-keyring"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: authURL.path))
    }

    func testAutoModeFallsBackToPrivateAuthFileWhenKeychainWriteFails() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = FakeOfficialKeychain()
        keychain.saveError = CodexAccountError.keychainFailure("test")
        let store = makeStore(home: directory, mode: .auto, keychain: keychain)

        try store.replace(with: authData("fallback"))

        let authURL = directory.appendingPathComponent("auth.json")
        XCTAssertEqual(try Data(contentsOf: authURL), authData("fallback"))
        let attributes = try FileManager.default.attributesOfItem(atPath: authURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testInvalidKeychainCredentialIsRejected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = FakeOfficialKeychain()
        keychain.data = Data("invalid".utf8)
        let store = makeStore(home: directory, mode: .keyring, keychain: keychain)

        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? CodexAccountError, .invalidAuthCache)
        }
    }

    private func makeStore(
        home: URL,
        mode: CodexAuthCredentialsStoreMode,
        keychain: FakeOfficialKeychain
    ) -> CodexAuthCredentialStore {
        CodexAuthCredentialStore(
            codexHome: home,
            modeResolver: FixedModeResolver(mode: mode),
            officialKeychain: keychain
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAuthCredentialStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func authData(_ value: String) -> Data {
        Data("{\"tokens\":{\"access_token\":\"\(value)\"}}".utf8)
    }
}

private struct FixedModeResolver: CodexAuthStoreModeResolving {
    let mode: CodexAuthCredentialsStoreMode
    func resolveMode() -> CodexAuthCredentialsStoreMode { mode }
}

private final class FakeOfficialKeychain: CodexOfficialKeychainHandling {
    var data: Data?
    var saveError: Error?
    private(set) var lastAccount: String?

    func read(account: String) throws -> Data? {
        lastAccount = account
        return data
    }

    func save(_ data: Data, account: String) throws {
        lastAccount = account
        if let saveError { throw saveError }
        self.data = data
    }
}
