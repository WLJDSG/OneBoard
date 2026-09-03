import Foundation
import XCTest
@testable import OneBoardKit

final class CodexAuthCredentialStoreTests: XCTestCase {
    func testReadForcesFileModeAndPreservesOtherConfig() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try authData("file").write(to: directory.appendingPathComponent("auth.json"))
        let config = """
        cli_auth_credentials_store = "keyring"
        model = "gpt-test"

        [mcp_servers.demo]
        command = "demo"
        """
        try Data(config.utf8).write(to: directory.appendingPathComponent("config.toml"))
        let store = CodexAuthCredentialStore(codexHome: directory)

        XCTAssertEqual(try store.read(), authData("file"))

        let updated = try String(contentsOf: directory.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(updated.hasPrefix("cli_auth_credentials_store = \"file\""))
        XCTAssertTrue(updated.contains("model = \"gpt-test\""))
        XCTAssertTrue(updated.contains("[mcp_servers.demo]"))
    }

    func testReplaceWritesPrivateAuthFileAndCreatesConfigBackupOnce() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        try Data("cli_auth_credentials_store = \"keyring\"\n".utf8).write(to: configURL)
        let store = CodexAuthCredentialStore(codexHome: directory)

        try store.replace(with: authData("first"))
        try store.replace(with: authData("second"))

        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("auth.json")), authData("second"))
        XCTAssertEqual(
            try String(contentsOf: configURL.appendingPathExtension("oneboard-auth-store-backup"), encoding: .utf8),
            "cli_auth_credentials_store = \"keyring\"\n"
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("auth.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testInvalidCredentialIsRejectedBeforeChangingConfig() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        try Data("cli_auth_credentials_store = \"keyring\"\n".utf8).write(to: configURL)
        let store = CodexAuthCredentialStore(codexHome: directory)

        XCTAssertThrowsError(try store.replace(with: Data("invalid".utf8))) { error in
            XCTAssertEqual(error as? CodexAccountError, .invalidAuthCache)
        }
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), "cli_auth_credentials_store = \"keyring\"\n")
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
