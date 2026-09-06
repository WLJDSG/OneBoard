import XCTest
import GRDB
@testable import OneBoardKit

final class AIProviderUsageTests: XCTestCase {
    func testQuotaFailureDoesNotClaimProxyFailure() {
        XCTAssertEqual(AIProviderQuotaError("额度查询 HTTP 404").localizedDescription, "额度查询 HTTP 404")
    }

    func testDeepSeekAnthropicConnectionUsesRootBalanceEndpoint() throws {
        for suffix in ["/anthropic", "/anthropic/v1/messages", "/v1/chat/completions"] {
            let profile = AIProviderProfile(client: .claude, title: "DeepSeek", baseURL: "https://api.deepseek.com" + suffix, model: "m")
            XCTAssertEqual(try AIProviderUsageService.endpoint(profile).0.absoluteString,
                           "https://api.deepseek.com/user/balance")
        }
    }

    func testDeepSeekBalanceDoesNotInventTokenCounts() throws {
        let snapshot = try AIProviderUsageService.parse(Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"12.3456"}]}"#.utf8), api: .deepseek, credentialID: "key")
        XCTAssertEqual(snapshot.balance, "12.3456 CNY")
        XCTAssertNil(snapshot.todayTokens)
        XCTAssertNil(snapshot.totalTokens)
    }

    func testSub2APISeparatesDailyLifetimeAndCachedTokens() throws {
        let data = Data(#"{"remaining":9.5,"unit":"USD","usage":{"today":{"total_tokens":120,"cache_read_tokens":50},"total":{"total_tokens":1200,"cache_read_tokens":500}}}"#.utf8)
        let snapshot = try AIProviderUsageService.parse(data, api: .sub2api, credentialID: "key")
        XCTAssertEqual(snapshot.todayTokens, 120)
        XCTAssertEqual(snapshot.totalTokens, 1200)
        XCTAssertEqual(snapshot.todayCacheTokens, 50)
        XCTAssertEqual(snapshot.totalCacheTokens, 500)
    }

    func testUnrecognizedOrInvalidQuotaDoesNotBecomeZero() {
        for body in [#"{"data":[]}"#, #"{"isValid":false,"remaining":20}"#] {
            XCTAssertThrowsError(try AIProviderUsageService.parse(Data(body.utf8), api: .sub2api, credentialID: "key"))
        }
    }

    func testQuotaEndpointPreservesDeploymentPrefixAndOrigin() throws {
        let profile = AIProviderProfile(client: .codex, title: "Relay", baseURL: "https://relay.example/gateway/v1/responses", model: "model")
        XCTAssertEqual(try AIProviderUsageService.endpoint(profile).0.absoluteString, "https://relay.example/gateway/v1/usage")
        var deepseek = profile
        deepseek.baseURL = "https://api.deepseek.com/v1"
        XCTAssertEqual(try AIProviderUsageService.endpoint(deepseek).0.absoluteString, "https://api.deepseek.com/user/balance")
    }

    func testKeyIdentityGroupsClientsButSeparatesCredentials() {
        var profile = AIProviderProfile(client: .codex, title: "Relay", baseURL: "https://relay.example/v1", model: "m")
        let first = AIUsageIdentity.make(profile: profile, key: "first")
        profile.client = .claude
        XCTAssertEqual(first, AIUsageIdentity.make(profile: profile, key: "first"))
        XCTAssertNotEqual(first, AIUsageIdentity.make(profile: profile, key: "second"))
    }

    func testUsagePersistenceDeduplicationLocalDayAndLifetime() throws {
        let queue = try DatabaseQueue()
        try queue.write { try AIUsageStore.migrate($0) }
        let store = AIUsageStore(queue: queue)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = calendar.startOfDay(for: now).timeIntervalSince1970
        let event = AIUsageEvent(id: "request-1", credentialID: "key", timestamp: start,
                                 input: 100, output: 20, cacheRead: 50, cacheCreation: 10)
        try store.record(event)
        try store.record(event)
        try store.record(AIUsageEvent(id: "before", credentialID: "key", timestamp: start - 1,
                                     input: 5, output: 0, cacheRead: 3, cacheCreation: 0))
        try store.record(AIUsageEvent(id: "other", credentialID: "other-key", timestamp: start,
                                     input: 999, output: 0, cacheRead: 0, cacheCreation: 0))
        let reopened = AIUsageStore(queue: queue)
        let day = try reopened.totals(credentialID: "key", day: now, calendar: calendar)
        XCTAssertEqual(day.total, 180)
        XCTAssertEqual(day.cacheRead, 50)
        XCTAssertEqual(try reopened.totals(credentialID: "key").total, 188)
        XCTAssertEqual(try reopened.totals(credentialID: "key").cacheRead, 53)
    }

    func testProxyEventsPersistAcrossSplitLinesAndIgnoreDuplicates() throws {
        let queue = try DatabaseQueue()
        try queue.write { try AIUsageStore.migrate($0) }
        let store = AIUsageStore(queue: queue)
        let reader = AIProxyUsageReader(identities: ["profile": "key"], store: store)
        let line = #"{"status":"usage","id":"request","providerID":"profile","timestamp":1800000000,"input":40,"output":20,"cacheRead":60,"cacheCreation":0}"# + "\n"
        let bytes = Data(line.utf8)
        reader.consume(bytes.prefix(30))
        reader.consume(bytes.dropFirst(30))
        reader.consume(bytes)
        let totals = try store.totals(credentialID: "key")
        XCTAssertEqual(totals.total, 120)
        XCTAssertEqual(totals.cacheRead, 60)
    }

    func testDeepSeekTranslationRecognizesTopLevelCacheHits() throws {
        let data = Data(#"{"choices":[{"message":{"content":"你好"}}],"usage":{"prompt_tokens":100,"completion_tokens":20,"prompt_cache_hit_tokens":80}}"#.utf8)
        let result = try ConfiguredAITranslationService.parse(data, format: .openAIChat)
        XCTAssertEqual(result.usage?.input, 20)
        XCTAssertEqual(result.usage?.read, 80)
    }

    func testTranslationUsesSelectedProviderKeyModelAndURL() throws {
        let profile = AIProviderProfile(client: .codex, title: "My API", baseURL: "https://relay.example/v1", model: "custom-model", apiFormat: .openAIChat)
        let request = try ConfiguredAITranslationService.request(profile: profile, key: "selected-key", text: "Hello", source: "en", target: "zh-Hans")
        XCTAssertEqual(request.url?.absoluteString, "https://relay.example/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer selected-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "custom-model")
        XCTAssertEqual(body["stream"] as? Bool, false)
    }

    func testDeepSeekAnthropicTranslationUsesOfficialCompatibilityPath() throws {
        let profile = AIProviderProfile(client: .claude, title: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-v4-pro[1M]", apiFormat: .anthropic)
        let request = try ConfiguredAITranslationService.request(profile: profile, key: "key", text: "Hello", source: nil, target: "zh-Hans")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/anthropic/v1/messages")
    }

    func testTranslationCacheIsIncludedExactlyOnce() throws {
        let data = Data(#"{"choices":[{"message":{"content":"你好"}}],"usage":{"prompt_tokens":100,"completion_tokens":20,"prompt_tokens_details":{"cached_tokens":60}}}"#.utf8)
        let result = try ConfiguredAITranslationService.parse(data, format: .openAIChat)
        XCTAssertEqual(result.text, "你好")
        XCTAssertEqual(result.usage?.input, 40)
        XCTAssertEqual(result.usage?.read, 60)
        XCTAssertEqual(result.usage?.output, 20)
    }

    func testTranslationParsesAnthropicResponsesAndGemini() throws {
        let cases: [(AIUpstreamAPIFormat, String)] = [
            (.anthropic, #"{"content":[{"type":"text","text":"你好"}],"usage":{"input_tokens":10,"output_tokens":2,"cache_read_input_tokens":6,"cache_creation_input_tokens":4}}"#),
            (.openAIResponses, #"{"output":[{"type":"message","content":[{"type":"output_text","text":"你好"}]}]}"#),
            (.geminiNative, #"{"candidates":[{"content":{"parts":[{"text":"你好"}]}}]}"#)
        ]
        for (format, body) in cases {
            let result = try ConfiguredAITranslationService.parse(Data(body.utf8), format: format)
            XCTAssertEqual(result.text, "你好")
            if format == .anthropic {
                XCTAssertEqual(result.usage?.input, 10)
                XCTAssertEqual(result.usage?.read, 6)
                XCTAssertEqual(result.usage?.creation, 4)
            } else { XCTAssertNil(result.usage) }
        }
    }
}
