import XCTest
@testable import OneBoardKit

final class AIModelConfigurationWriterTests: XCTestCase {
    func testCodexCustomSwitchPreservesUnrelatedConfigAndDoesNotNeedAuthFile() throws {
        let context = try makeContext()
        let existing = """
        model = "old-model"
        model_provider = "old-provider"
        model_reasoning_effort = "high"

        [projects."/tmp/example"]
        trust_level = "trusted"
        """
        try existing.write(to: context.codexURL, atomically: true, encoding: .utf8)
        let profile = AIProviderProfile(
            client: .codex,
            title: "Relay",
            baseURL: "https://relay.example/v1",
            model: "gpt-test"
        )

        try context.writer.apply(profile, apiKey: "secret-token")

        let output = try String(contentsOf: context.codexURL, encoding: .utf8)
        XCTAssertTrue(output.contains("model_provider = \"oneboard\""))
        XCTAssertTrue(output.contains("model = \"gpt-test\""))
        XCTAssertTrue(output.contains("model_reasoning_effort = \"high\""))
        XCTAssertTrue(output.contains("[projects.\"/tmp/example\"]"))
        XCTAssertTrue(output.contains("[model_providers.oneboard]"))
        XCTAssertTrue(output.contains("experimental_bearer_token = \"secret-token\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.directory.appendingPathComponent("auth.json").path))
    }

    func testCodexOfficialSwitchRemovesManagedProviderAndKeepsOtherTables() throws {
        let context = try makeContext()
        let existing = """
        model_provider = "oneboard"
        model = "old-model"

        [model_providers.oneboard]
        name = "Relay"
        base_url = "https://relay.example/v1"
        experimental_bearer_token = "secret-token"

        [mcp_servers.demo]
        command = "demo"
        """
        try existing.write(to: context.codexURL, atomically: true, encoding: .utf8)
        let profile = AIProviderProfile(client: .codex, kind: .official, title: "Official", model: "gpt-official")

        try context.writer.apply(profile, apiKey: nil)

        let output = try String(contentsOf: context.codexURL, encoding: .utf8)
        XCTAssertTrue(output.contains("model = \"gpt-official\""))
        XCTAssertFalse(output.contains("model_provider ="))
        XCTAssertFalse(output.contains("[model_providers.oneboard]"))
        XCTAssertFalse(output.contains("secret-token"))
        XCTAssertTrue(output.contains("[mcp_servers.demo]"))
    }

    func testClaudeSwitchMergesEnvironmentAndPreservesUnknownFields() throws {
        let context = try makeContext()
        let existing: [String: Any] = [
            "permissions": ["allow": ["Bash(*)"]],
            "env": [
                "KEEP_ME": "yes",
                "ANTHROPIC_API_KEY": "old-key",
                "ANTHROPIC_MODEL": "old-model",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        try data.write(to: context.claudeURL)
        let profile = AIProviderProfile(
            client: .claude,
            title: "Claude Relay",
            baseURL: "https://claude.example/anthropic",
            model: "claude-test",
            claudeAPIKeyField: .authToken
        )

        try context.writer.apply(profile, apiKey: "new-key")

        let outputData = try Data(contentsOf: context.claudeURL)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: outputData) as? [String: Any])
        XCTAssertNotNil(output["permissions"])
        let env = try XCTUnwrap(output["env"] as? [String: String])
        XCTAssertEqual(env["KEEP_ME"], "yes")
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "https://claude.example/anthropic")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"], "new-key")
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_OPUS_MODEL"], "claude-test")
    }

    func testBackupIsCreatedOnceAndCanBeRestored() throws {
        let context = try makeContext()
        let original = "model = \"original\"\n"
        try original.write(to: context.codexURL, atomically: true, encoding: .utf8)
        let first = AIProviderProfile(client: .codex, kind: .official, title: "First", model: "first")
        let second = AIProviderProfile(client: .codex, kind: .official, title: "Second", model: "second")

        try context.writer.apply(first, apiKey: nil)
        try context.writer.apply(second, apiKey: nil)
        try context.writer.restoreBackup(for: .codex)

        XCTAssertEqual(try String(contentsOf: context.codexURL, encoding: .utf8), original)
    }

    func testRejectsSymbolicLinkConfigurationPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("real.toml")
        try "model = \"real\"".write(to: destination, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        let writer = AIModelConfigurationWriter(
            codexConfigURL: link,
            claudeSettingsURL: directory.appendingPathComponent("settings.json")
        )
        let profile = AIProviderProfile(client: .codex, kind: .official, title: "Official", model: "gpt-test")

        XCTAssertThrowsError(try writer.apply(profile, apiKey: nil)) { error in
            guard case AIModelSwitchError.unsafePath = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCustomProfileRequiresHTTPURL() {
        let profile = AIProviderProfile(client: .codex, title: "Bad", baseURL: "file:///tmp/api", model: "gpt-test")
        XCTAssertThrowsError(try profile.validated())
    }

    private func makeContext() throws -> (
        writer: AIModelConfigurationWriter,
        directory: URL,
        codexURL: URL,
        claudeURL: URL
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let codexURL = directory.appendingPathComponent("config.toml")
        let claudeURL = directory.appendingPathComponent("settings.json")
        return (
            AIModelConfigurationWriter(codexConfigURL: codexURL, claudeSettingsURL: claudeURL),
            directory,
            codexURL,
            claudeURL
        )
    }
}

final class AIProviderStoreTests: XCTestCase {
    func testProfilesAndActiveIDsRemainSeparatedByClient() throws {
        let suiteName = "AIProviderStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let store = AIProviderStore(
            defaults: defaults,
            profilesKey: "profiles",
            activeCodexKey: "codex",
            activeClaudeKey: "claude"
        )
        let codex = AIProviderProfile(client: .codex, kind: .official, title: "Codex", model: "gpt-test")
        let claude = AIProviderProfile(client: .claude, kind: .official, title: "Claude", model: "claude-test")

        store.save(codex)
        store.save(claude)
        store.setActiveID(codex.id, for: .codex)
        store.setActiveID(claude.id, for: .claude)

        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.activeID(for: .codex), codex.id)
        XCTAssertEqual(store.activeID(for: .claude), claude.id)
    }
}
