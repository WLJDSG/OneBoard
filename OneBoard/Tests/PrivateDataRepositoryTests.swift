import Foundation
import GRDB
import XCTest
@testable import OneBoardKit

final class PrivateDataRepositoryTests: XCTestCase {
    func testSQLiteVaultsPersistCredentialsWithoutKeychain() throws {
        let context = try makeContext()
        let accountID = UUID()
        let profileID = UUID()
        let codexVault = SQLiteCodexAuthCacheVault(repository: context.repository)
        let aiVault = SQLiteAIProviderSecretVault(repository: context.repository)

        try codexVault.save(Data("{\"token\":\"codex\"}".utf8), for: accountID)
        try aiVault.save("provider-secret", for: profileID)

        XCTAssertEqual(try codexVault.load(for: accountID), Data("{\"token\":\"codex\"}".utf8))
        XCTAssertEqual(try aiVault.load(for: profileID), "provider-secret")
        XCTAssertTrue(aiVault.contains(profileID: profileID))
    }

    func testApplicationSecretMigratesLegacyPreferenceIntoSQLite() throws {
        let context = try makeContext()
        let suite = "ApplicationSecretStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy-secret", forKey: "api-key")
        let store = ApplicationSecretStore(repository: context.repository, legacyDefaults: defaults)

        XCTAssertEqual(store.value(for: "api-key"), "legacy-secret")
        XCTAssertNil(defaults.string(forKey: "api-key"))
        XCTAssertEqual(
            try context.repository.load(namespace: "application_secret", recordID: "api-key"),
            Data("legacy-secret".utf8)
        )
    }

    func testCCSwitchImportPersistsProfilesKeysAndCurrentSelection() throws {
        let context = try makeContext()
        let sourceURL = context.directory.appendingPathComponent("cc-switch.db")
        let source = try DatabaseQueue(path: sourceURL.path)
        try source.write { db in
            try db.execute(sql: """
                CREATE TABLE providers (
                    id TEXT, app_type TEXT, name TEXT, settings_config TEXT,
                    is_current BOOLEAN, sort_index INTEGER, created_at INTEGER
                )
                """)
            let codexSettings: [String: Any] = [
                "auth": ["OPENAI_API_KEY": "codex-key"],
                "config": "model_provider = \"relay\"\nmodel = \"gpt-test\"\n[model_providers.relay]\nbase_url = \"https://relay.example\"\n",
            ]
            let claudeSettings: [String: Any] = [
                "env": [
                    "ANTHROPIC_BASE_URL": "https://claude.example",
                    "ANTHROPIC_AUTH_TOKEN": "claude-key",
                    "ANTHROPIC_MODEL": "claude-test",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "haiku-test",
                ],
            ]
            try db.execute(
                sql: "INSERT INTO providers VALUES (?, 'codex', 'Codex Relay', ?, 1, 0, 1)",
                arguments: ["codex-id", try json(codexSettings)]
            )
            try db.execute(
                sql: "INSERT INTO providers VALUES (?, 'claude', 'Claude Relay', ?, 1, 0, 1)",
                arguments: ["claude-id", try json(claudeSettings)]
            )
        }
        let store = AIProviderStore(repository: context.repository, legacyDefaults: UserDefaults())
        let vault = SQLiteAIProviderSecretVault(repository: context.repository)

        let summary = try OneBoardMaintenance.importCCSwitch(
            store: store,
            vault: vault,
            importer: CCSwitchProviderImporter(databaseURL: sourceURL)
        )

        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertTrue(summary.skippedNames.isEmpty)
        XCTAssertEqual(store.profiles.count, 2)
        let codex = try XCTUnwrap(store.profiles.first { $0.client == .codex })
        let claude = try XCTUnwrap(store.profiles.first { $0.client == .claude })
        XCTAssertEqual(try vault.load(for: codex.id), "codex-key")
        XCTAssertEqual(try vault.load(for: claude.id), "claude-key")
        XCTAssertEqual(claude.claudeHaikuModel, "haiku-test")
        XCTAssertEqual(store.activeID(for: .codex), codex.id)
        XCTAssertEqual(store.activeID(for: .claude), claude.id)
    }

    private func makeContext() throws -> (directory: URL, repository: PrivateDataRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateDataRepositoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("oneboard.sqlite").path)
        try queue.write { try V5_CreatePrivateDataTables.migrate($0) }
        return (directory, PrivateDataRepository(queue: queue))
    }

    private func json(_ object: [String: Any]) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
}
