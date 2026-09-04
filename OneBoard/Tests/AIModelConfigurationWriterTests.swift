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
            model: "default-test",
            claudeAPIKeyField: .authToken,
            claudeHaikuModel: "haiku-test[1M]",
            claudeHaikuModelName: "Fast",
            claudeSonnetModel: "sonnet-test",
            claudeSonnetModelName: "Balanced",
            claudeOpusModel: "opus-test",
            claudeOpusModelName: "Strong",
            claudeFableModel: "fable-test[1M]",
            claudeFableModelName: "Long context",
            claudeSubagentModel: "subagent-test"
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
        XCTAssertEqual(env["ANTHROPIC_MODEL"], "default-test")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"], "haiku-test[1M]")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"], "Fast")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_SONNET_MODEL"], "sonnet-test")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"], "Balanced")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_OPUS_MODEL"], "opus-test")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"], "Strong")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_FABLE_MODEL"], "fable-test[1M]")
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"], "Long context")
        XCTAssertEqual(env["CLAUDE_CODE_SUBAGENT_MODEL"], "subagent-test")
    }

    func testProxyRoutingWritesOnlyPlaceholderToClientConfigs() throws {
        let context = try makeContext()
        let codex = AIProviderProfile(
            client: .codex,
            title: "Relay",
            baseURL: "https://upstream.example/v1",
            model: "gpt-test"
        )
        try context.writer.apply(
            codex,
            apiKey: "must-not-reach-client-config",
            routing: AIProxyRouting(baseURL: "http://127.0.0.1:43123/v1")
        )
        let codexText = try String(contentsOf: context.codexURL, encoding: .utf8)
        XCTAssertTrue(codexText.contains("base_url = \"http://127.0.0.1:43123/v1\""))
        XCTAssertTrue(codexText.contains("experimental_bearer_token = \"PROXY_MANAGED\""))
        XCTAssertFalse(codexText.contains("must-not-reach-client-config"))

        let claude = AIProviderProfile(
            client: .claude,
            title: "Relay",
            baseURL: "https://upstream.example",
            model: "claude-test"
        )
        try context.writer.apply(
            claude,
            apiKey: "must-not-reach-client-config",
            routing: AIProxyRouting(baseURL: "http://127.0.0.1:43123")
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: context.claudeURL)) as? [String: Any]
        )
        let env = try XCTUnwrap(root["env"] as? [String: String])
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "http://127.0.0.1:43123")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"], "PROXY_MANAGED")
        XCTAssertFalse(String(data: try Data(contentsOf: context.claudeURL), encoding: .utf8)!.contains("must-not-reach-client-config"))
    }

    func testProxySnapshotCarriesCCSwitchRuntimeMetadataAndSecretOnlyInMemoryPayload() throws {
        let profile = AIProviderProfile(
            client: .claude,
            title: "Converted Relay",
            baseURL: "https://relay.example/v1",
            model: "claude-test",
            apiFormat: .openAIResponses,
            isFullURL: true,
            customUserAgent: "OneBoard-Test",
            requestHeaderOverridesJSON: "{\"x-route\":\"work\"}",
            requestBodyOverridesJSON: "{\"temperature\":0.2}",
            promptCacheKey: "stable-cache"
        )

        let data = try AIProxySnapshotBuilder.makePayload(providers: [(profile, "sqlite-secret")])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((root["listenPort"] as? NSNumber)?.intValue, 15731)
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        let provider = try XCTUnwrap(providers.first?["provider"] as? [String: Any])
        let settings = try XCTUnwrap(provider["settingsConfig"] as? [String: Any])
        let env = try XCTUnwrap(settings["env"] as? [String: Any])
        let meta = try XCTUnwrap(provider["meta"] as? [String: Any])
        let overrides = try XCTUnwrap(meta["localProxyRequestOverrides"] as? [String: Any])

        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"] as? String, "sqlite-secret")
        XCTAssertEqual(meta["apiFormat"] as? String, "openai_responses")
        XCTAssertEqual(meta["isFullUrl"] as? Bool, true)
        XCTAssertEqual(meta["customUserAgent"] as? String, "OneBoard-Test")
        XCTAssertEqual((overrides["headers"] as? [String: String])?["x-route"], "work")
        XCTAssertEqual((overrides["body"] as? [String: Double])?["temperature"], 0.2)
    }

    func testProxySnapshotUpdatesImportedCodexModelAndURLWithoutDroppingOtherConfig() throws {
        let profile = AIProviderProfile(
            client: .codex,
            title: "Imported Relay",
            baseURL: "https://new.example/v1",
            model: "new-model",
            runtimeSettingsJSON: """
            {"auth":{},"config":"model_provider = \\"relay\\"\\nmodel = \\"old-model\\"\\nmodel_reasoning_effort = \\"high\\"\\n[model_providers.relay]\\nbase_url = \\"https://old.example/v1\\"\\nwire_api = \\"responses\\"\\n"}
            """
        )

        let data = try AIProxySnapshotBuilder.makePayload(providers: [(profile, "sqlite-secret")])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        let provider = try XCTUnwrap(providers.first?["provider"] as? [String: Any])
        let settings = try XCTUnwrap(provider["settingsConfig"] as? [String: Any])
        let config = try XCTUnwrap(settings["config"] as? String)

        XCTAssertTrue(config.contains("model = \"new-model\""))
        XCTAssertTrue(config.contains("base_url = \"https://new.example/v1\""))
        XCTAssertTrue(config.contains("model_reasoning_effort = \"high\""))
        XCTAssertFalse(config.contains("old-model"))
        XCTAssertFalse(config.contains("old.example"))
    }

    func testClaudeFableFallsBackToOpusThenDefaultModel() throws {
        let context = try makeContext()
        let opusProfile = AIProviderProfile(
            client: .claude,
            kind: .official,
            title: "Claude",
            model: "default-test",
            claudeOpusModel: "opus-test"
        )

        try context.writer.apply(opusProfile, apiKey: nil)

        var output = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: context.claudeURL)) as? [String: Any]
        )
        var env = try XCTUnwrap(output["env"] as? [String: String])
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_FABLE_MODEL"], "opus-test")

        let defaultProfile = AIProviderProfile(
            client: .claude,
            kind: .official,
            title: "Claude",
            model: "default-test"
        )
        try context.writer.apply(defaultProfile, apiKey: nil)
        output = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: context.claudeURL)) as? [String: Any]
        )
        env = try XCTUnwrap(output["env"] as? [String: String])
        XCTAssertEqual(env["ANTHROPIC_DEFAULT_FABLE_MODEL"], "default-test")
    }

    func testOfficialCodexQuotaPresentationUsesActiveAccountSnapshot() {
        let profile = AIProviderProfile(
            client: .codex,
            kind: .official,
            title: "OpenAI Official",
            model: "gpt-test"
        )
        let account = CodexAccountProfile(
            title: "work@example.com",
            status: CodexAccountStatusSnapshot(
                fiveHour: CodexUsageWindowSnapshot(remainingPercent: 82, resetAt: nil, windowMinutes: 300),
                weekly: CodexUsageWindowSnapshot(remainingPercent: 61, resetAt: nil, windowMinutes: nil),
                resetCreditsAvailable: nil,
                subscriptionActiveUntil: nil,
                fetchedAt: Date()
            )
        )

        XCTAssertEqual(
            AIProviderQuotaPresentation.make(profile: profile, activeCodexAccount: account),
            AIProviderQuotaPresentation(
                text: "额度：5 小时 82% · 每周 61% · work@example.com",
                tone: .normal
            )
        )
    }

    func testCustomProviderQuotaPresentationDoesNotPretendToKnowBalance() {
        let profile = AIProviderProfile(
            client: .claude,
            title: "Relay",
            baseURL: "https://relay.example",
            model: "relay-model"
        )

        XCTAssertEqual(
            AIProviderQuotaPresentation.make(profile: profile, activeCodexAccount: nil),
            AIProviderQuotaPresentation(text: "额度：未配置查询", tone: .unavailable)
        )
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

    func testProviderWebsiteRequiresHTTPURLAndMetadataIsTrimmed() throws {
        let invalid = AIProviderProfile(
            client: .claude,
            title: "Relay",
            websiteURL: "file:///tmp/provider",
            baseURL: "https://relay.example",
            model: "claude-test"
        )
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? AIModelSwitchError, .invalidProfile("官网链接必须是有效的 HTTP(S) URL"))
        }

        let valid = AIProviderProfile(
            client: .claude,
            title: " Relay ",
            note: " Company account ",
            websiteURL: " https://relay.example/docs ",
            baseURL: "https://relay.example",
            model: "claude-test"
        )
        let validated = try valid.validated()
        XCTAssertEqual(validated.title, "Relay")
        XCTAssertEqual(validated.note, "Company account")
        XCTAssertEqual(validated.websiteURL, "https://relay.example/docs")
    }

    func testLegacyProviderWithoutPresentationMetadataStillDecodes() throws {
        let profile = AIProviderProfile(
            client: .claude,
            title: "Legacy",
            baseURL: "https://relay.example",
            model: "claude-test"
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
        object.removeValue(forKey: "note")
        object.removeValue(forKey: "websiteURL")

        let decoded = try JSONDecoder().decode(
            AIProviderProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(decoded.note)
        XCTAssertNil(decoded.websiteURL)
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
