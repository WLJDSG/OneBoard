import AppKit
import XCTest
@testable import OneBoardKit

final class ProviderExperienceRegressionTests: XCTestCase {
    func testDeepSeekClaudeCatalogUsesRootModelsEndpoint() {
        for path in ["/anthropic", "/anthropic/v1/messages", "/v1/chat/completions"] {
            XCTAssertEqual(AIProviderEditorView.modelCatalogURL(baseURL: "https://api.deepseek.com" + path)?.absoluteString,
                           "https://api.deepseek.com/models")
        }
    }

    func testCatalogIsNotTheFullInferenceURL() {
        XCTAssertEqual(AIProviderEditorView.modelCatalogURL(baseURL: "https://relay.example/gateway/v1/responses", isFullURL: true)?.absoluteString,
                       "https://relay.example/gateway/v1/models")
    }

    func testTranslationRecognizesCompleteURLWithoutToggle() throws {
        for (path, format) in [("/v1/chat/completions", AIUpstreamAPIFormat.openAIChat), ("/v1/responses", .openAIResponses), ("/v1/messages", .anthropic)] {
            let url = "https://relay.example/gateway" + path
            let profile = AIProviderProfile(client: .claude, title: "Relay", baseURL: url, model: "m", apiFormat: format)
            let request = try ConfiguredAITranslationService.request(profile: profile, key: "test", text: "hi", source: nil, target: "en")
            XCTAssertEqual(request.url?.absoluteString, url)
        }
    }

    @MainActor
    func testSettingsContentDoesNotMoveWindow() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        SettingsWindowManager.configureDragging(window)
        XCTAssertFalse(window.isMovableByWindowBackground)
    }
}

extension ProviderExperienceRegressionTests {
    func testManualQuotaEndpointPersistsAndSeparatesOnlyQuotaCache() throws {
        var first = AIProviderProfile(client: .claude, title: "Relay", baseURL: "https://relay.example/v1", model: "test", quotaAPI: .auto, quotaURL: "https://relay.example/account/quota")
        let restored = try JSONDecoder().decode(AIProviderProfile.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(try AIProviderUsageService.endpoint(restored).0.absoluteString, "https://relay.example/account/quota")
        first.quotaURL = "https://relay.example/account/other"
        XCTAssertNotEqual(AIUsageIdentity.quota(profile: first, key: "fake"), AIUsageIdentity.quota(profile: restored, key: "fake"))
        XCTAssertEqual(AIUsageIdentity.make(profile: first, key: "fake"), AIUsageIdentity.make(profile: restored, key: "fake"))
    }

    func testPresetEndpointsDoNotAppendAnExtraVersion() throws {
        let cases = [
            ("https://api.ppio.com/v3/openai", "https://api.ppio.com/v3/openai/chat/completions"),
            ("https://open.bigmodel.cn/api/coding/paas/v4", "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"),
            ("https://generativelanguage.googleapis.com/v1beta/openai", "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        ]
        for (base, expected) in cases { XCTAssertEqual(AIEndpointResolver.requestURL(baseURL: base, format: .openAIChat, model: "test")?.absoluteString, expected) }
        XCTAssertEqual(Set(AIProviderPreset.all.map(\.id)).count, AIProviderPreset.all.count)
    }

    func testOwnedProcessQuitHasABoundedWait() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        let start = Date()
        OwnedProcessTermination.stop(process, gracePeriod: 0.1)
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}

extension ProviderExperienceRegressionTests {
    func testPresetRuntimeReceivesCompleteUpstreamURL() throws {
        let profile = AIProviderProfile(client: .claude, title: "PPIO", baseURL: "https://api.ppio.com/v3/openai", model: "test", presetID: "ppio", apiFormat: .openAIChat)
        let data = try AIProxySnapshotBuilder.makePayload(providers: [(profile, "fake-key")])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        let provider = try XCTUnwrap(providers.first?["provider"] as? [String: Any])
        let settings = try XCTUnwrap(provider["settingsConfig"] as? [String: Any])
        let env = try XCTUnwrap(settings["env"] as? [String: String])
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "https://api.ppio.com/v3/openai/chat/completions")
        XCTAssertEqual((provider["meta"] as? [String: Any])?["isFullUrl"] as? Bool, true)
    }

    func testReorderMovesNeighborsAndPreservesAllRows() {
        let ids = [UUID(), UUID(), UUID()]
        XCTAssertEqual(SettingsReorder.moving(ids[1], relativeTo: ids[0], after: false, in: ids), [ids[1], ids[0], ids[2]])
        XCTAssertEqual(SettingsReorder.moving(ids[2], relativeTo: ids[1], after: false, in: ids), [ids[0], ids[2], ids[1]])
        XCTAssertEqual(SettingsReorder.moving(ids[0], relativeTo: ids[2], after: true, in: ids), [ids[1], ids[2], ids[0]])
    }
}
