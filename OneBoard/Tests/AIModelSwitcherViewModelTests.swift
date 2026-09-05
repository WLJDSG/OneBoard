import XCTest
@testable import OneBoardKit

@MainActor
final class AIModelSwitcherViewModelTests: XCTestCase {
    func testCodexSwitchRestartsRunningApplicationAfterWritingConfiguration() async throws {
        let suiteName = "AIModelSwitcherViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let events = AIModelSwitchEventLog()
        let store = AIProviderStore(
            defaults: defaults,
            profilesKey: "profiles",
            activeCodexKey: "codex",
            activeClaudeKey: "claude"
        )
        let profile = AIProviderProfile(
            client: .codex,
            title: "Relay",
            baseURL: "https://relay.example/v1",
            model: "gpt-test"
        )
        store.save(profile)
        let vault = AIModelSwitchSecretVault(secrets: [profile.id: "secret-token"])
        let lifecycle = AIModelSwitchLifecycle(events: events, isRunning: true)
        let viewModel = AIModelSwitcherViewModel(
            store: store,
            vault: vault,
            writer: AIModelSwitchWriter(events: events),
            proxyCoordinator: AIModelSwitchProxy(events: events),
            applicationLifecycle: lifecycle
        )

        let message = await viewModel.switchProfile(id: profile.id)

        XCTAssertEqual(events.values, ["proxy.prepare", "codex.close", "config.write", "codex.launch"])
        XCTAssertEqual(store.activeID(for: .codex), profile.id)
        XCTAssertEqual(message, "已切换 Codex 到 Relay / gpt-test；Codex 已重新打开")
    }

    func testSavingActiveCodexProviderReloadsProxyAndApplication() async throws {
        let suiteName = "AIModelSwitcherViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let events = AIModelSwitchEventLog()
        let store = AIProviderStore(
            defaults: defaults,
            profilesKey: "profiles",
            activeCodexKey: "codex",
            activeClaudeKey: "claude"
        )
        let profile = AIProviderProfile(
            client: .codex,
            title: "Relay",
            baseURL: "https://relay.example/v1",
            model: "old-model"
        )
        store.save(profile)
        store.setActiveID(profile.id, for: .codex)
        let vault = AIModelSwitchSecretVault(secrets: [profile.id: "old-token"])
        let viewModel = AIModelSwitcherViewModel(
            store: store,
            vault: vault,
            writer: AIModelSwitchWriter(events: events),
            proxyCoordinator: AIModelSwitchProxy(events: events),
            applicationLifecycle: AIModelSwitchLifecycle(events: events, isRunning: true)
        )
        var updated = profile
        updated.model = "new-model"

        try await viewModel.save(updated, apiKey: "new-token")

        XCTAssertEqual(events.values, ["proxy.prepare", "codex.close", "config.write", "codex.launch"])
        XCTAssertEqual(try vault.load(for: profile.id), "new-token")
        XCTAssertEqual(store.profiles.first?.model, "new-model")
    }

    func testCodexSwitchKeepsPreviousSelectionWhenApplicationCannotClose() async throws {
        let context = try makeSwitchContext()
        context.lifecycle.closeError = CodexAccountError.applicationCloseFailed

        let message = await context.viewModel.switchProfile(id: context.target.id)

        XCTAssertEqual(context.events.values, ["proxy.prepare", "codex.close", "proxy.restore"])
        XCTAssertEqual(context.store.activeID(for: .codex), context.current.id)
        XCTAssertEqual(message, CodexAccountError.applicationCloseFailed.localizedDescription)
    }

    func testCodexSwitchKeepsNewSelectionWhenOnlyRelaunchFails() async throws {
        let context = try makeSwitchContext()
        context.lifecycle.launchError = CodexAccountError.applicationLaunchFailed

        let message = await context.viewModel.switchProfile(id: context.target.id)

        XCTAssertEqual(context.events.values, ["proxy.prepare", "codex.close", "config.write", "codex.launch"])
        XCTAssertEqual(context.store.activeID(for: .codex), context.target.id)
        XCTAssertEqual(message, "已切换 Codex 到 Relay / gpt-test，但 Codex 重新打开失败，请手动打开")
    }

    func testSaveAndSwitchActivatesNewCodexProvider() async throws {
        let suiteName = "AIModelSwitcherViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AIProviderStore(
            defaults: defaults,
            profilesKey: "profiles",
            activeCodexKey: "codex",
            activeClaudeKey: "claude"
        )
        let profile = AIProviderProfile(
            client: .codex,
            title: "Relay",
            baseURL: "https://relay.example/v1",
            model: "gpt-test"
        )
        let events = AIModelSwitchEventLog()
        let viewModel = AIModelSwitcherViewModel(
            store: store,
            vault: AIModelSwitchSecretVault(secrets: [:]),
            writer: AIModelSwitchWriter(events: events),
            proxyCoordinator: AIModelSwitchProxy(events: events),
            applicationLifecycle: AIModelSwitchLifecycle(events: events, isRunning: true)
        )

        try await viewModel.saveAndSwitch(profile, apiKey: "secret-token")

        XCTAssertEqual(store.activeID(for: .codex), profile.id)
        XCTAssertEqual(events.values, ["proxy.prepare", "codex.close", "config.write", "codex.launch"])
    }

    private func makeSwitchContext() throws -> (
        viewModel: AIModelSwitcherViewModel,
        store: AIProviderStore,
        current: AIProviderProfile,
        target: AIProviderProfile,
        lifecycle: AIModelSwitchLifecycle,
        events: AIModelSwitchEventLog
    ) {
        let suiteName = "AIModelSwitcherViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let store = AIProviderStore(
            defaults: defaults,
            profilesKey: "profiles",
            activeCodexKey: "codex",
            activeClaudeKey: "claude"
        )
        let current = AIProviderProfile(client: .codex, kind: .official, title: "Official", model: "gpt-official")
        let target = AIProviderProfile(
            client: .codex,
            title: "Relay",
            baseURL: "https://relay.example/v1",
            model: "gpt-test"
        )
        store.profiles = [current, target]
        store.setActiveID(current.id, for: .codex)
        let events = AIModelSwitchEventLog()
        let lifecycle = AIModelSwitchLifecycle(events: events, isRunning: true)
        let viewModel = AIModelSwitcherViewModel(
            store: store,
            vault: AIModelSwitchSecretVault(secrets: [target.id: "secret-token"]),
            writer: AIModelSwitchWriter(events: events),
            proxyCoordinator: AIModelSwitchProxy(events: events),
            applicationLifecycle: lifecycle
        )
        return (viewModel, store, current, target, lifecycle, events)
    }
}

private final class AIModelSwitchEventLog: @unchecked Sendable {
    var values: [String] = []
}

private final class AIModelSwitchSecretVault: AIProviderSecretVaulting {
    var secrets: [UUID: String]

    init(secrets: [UUID: String]) {
        self.secrets = secrets
    }

    func save(_ secret: String, for profileID: UUID) throws { secrets[profileID] = secret }
    func load(for profileID: UUID) throws -> String {
        guard let secret = secrets[profileID] else { throw AIModelSwitchError.apiKeyMissing }
        return secret
    }
    func contains(profileID: UUID) -> Bool { secrets[profileID] != nil }
    func delete(for profileID: UUID) throws { secrets.removeValue(forKey: profileID) }
}

private final class AIModelSwitchWriter: AIModelConfigurationWriting {
    let events: AIModelSwitchEventLog

    init(events: AIModelSwitchEventLog) {
        self.events = events
    }

    func apply(_ profile: AIProviderProfile, apiKey: String?, routing: AIProxyRouting?) throws {
        events.values.append("config.write")
    }

    func restoreBackup(for client: AIClient) throws {}
}

private final class AIModelSwitchProxy: AIProxyCoordinating {
    let events: AIModelSwitchEventLog

    init(events: AIModelSwitchEventLog) {
        self.events = events
    }

    func prepare(
        switching profile: AIProviderProfile,
        apiKey: String,
        profiles: [AIProviderProfile],
        activeIDs: [AIClient: UUID],
        secretLoader: (UUID) throws -> String
    ) throws -> AIProxyRouting {
        events.values.append("proxy.prepare")
        return AIProxyRouting(baseURL: "http://127.0.0.1:15731/v1")
    }

    func restore(
        profiles: [AIProviderProfile],
        activeIDs: [AIClient: UUID],
        secretLoader: (UUID) throws -> String
    ) throws {
        events.values.append("proxy.restore")
    }

    func stop() {}
}

@MainActor
private final class AIModelSwitchLifecycle: CodexApplicationLifecycleControlling {
    let events: AIModelSwitchEventLog
    var isRunning: Bool
    var closeError: Error?
    var launchError: Error?

    init(events: AIModelSwitchEventLog, isRunning: Bool) {
        self.events = events
        self.isRunning = isRunning
    }

    func closeAndWait() async throws {
        events.values.append("codex.close")
        if let closeError { throw closeError }
        isRunning = false
    }

    func launch() async throws {
        events.values.append("codex.launch")
        if let launchError { throw launchError }
        isRunning = true
    }
}
