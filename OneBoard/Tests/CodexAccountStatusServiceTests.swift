import Foundation
import XCTest
@testable import OneBoardKit

final class CodexAccountStatusServiceTests: XCTestCase {
    override func tearDown() {
        CodexStatusURLProtocol.handler = nil
        super.tearDown()
    }

    func testLegacyProfileWithoutStatusFieldsStillDecodes() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"旧账号","createdAt":0,"updatedAt":0}
        """

        let profile = try JSONDecoder().decode(CodexAccountProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.id, id)
        XCTAssertNil(profile.status)
        XCTAssertNil(profile.statusError)
    }

    func testUsageResponseBecomesRemainingQuotaSubscriptionAndResetCount() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let accessToken = jwt(["exp": 1_800_003_600])
        let authCache = authData(accessToken: accessToken, refreshToken: "refresh-old")
        CodexStatusURLProtocol.handler = { request in
            switch request.url?.path {
            case "/backend-api/wham/usage":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-1")
                return Self.response(request, json: [
                    "plan_type": "plus",
                    "rate_limit": [
                        "primary_window": ["used_percent": 34, "reset_at": 1_800_001_800, "limit_window_seconds": 18_000],
                        "secondary_window": ["used_percent": 21, "reset_after_seconds": 345_600, "limit_window_seconds": 604_800],
                    ],
                    "rate_limit_reset_credits": ["available_count": 1],
                ])
            case "/backend-api/accounts/check/v4-2023-04-27":
                return Self.response(request, json: [
                    "accounts": [[
                        "account_id": "account-1",
                        "plan_type": "plus",
                        "active_until": "2027-01-02T03:04:05Z",
                    ]],
                ])
            default:
                XCTFail("意外请求：\(request.url?.absoluteString ?? "nil")")
                return Self.response(request, status: 404, json: [:])
            }
        }

        let result = try await makeService(now: now).refreshStatus(
            authCache: authCache,
            accountID: "account-1",
            allowCredentialRefresh: true
        )

        XCTAssertEqual(result.status.fiveHour?.remainingPercent, 66)
        XCTAssertEqual(result.status.fiveHour?.windowMinutes, 300)
        XCTAssertEqual(result.status.weekly?.remainingPercent, 79)
        XCTAssertEqual(result.status.weekly?.windowMinutes, 10_080)
        XCTAssertEqual(result.status.resetCreditsAvailable, 1)
        XCTAssertEqual(result.planType, "plus")
        XCTAssertEqual(result.status.subscriptionActiveUntil, ISO8601DateFormatter().date(from: "2027-01-02T03:04:05Z"))
        XCTAssertNil(result.refreshedAuthCache)
    }

    func testProPrimaryWeeklyWindowIsNotMislabelledAsFiveHour() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let accessToken = jwt(["exp": 1_800_003_600])
        CodexStatusURLProtocol.handler = { request in
            switch request.url?.path {
            case "/backend-api/wham/usage":
                return Self.response(request, json: [
                    "plan_type": "pro",
                    "rate_limit": [
                        "primary_window": ["used_percent": 12, "limit_window_seconds": 604_800]
                    ]
                ])
            case "/backend-api/wham/rate-limit-reset-credits":
                return Self.response(request, json: ["available_count": 2])
            case "/backend-api/accounts/check/v4-2023-04-27":
                return Self.response(request, json: [:])
            default:
                return Self.response(request, status: 404, json: [:])
            }
        }
        let result = try await makeService(now: now).refreshStatus(
            authCache: authData(accessToken: accessToken, refreshToken: "refresh"),
            accountID: nil,
            allowCredentialRefresh: true
        )
        XCTAssertNil(result.status.fiveHour)
        XCTAssertEqual(result.status.weekly?.remainingPercent, 88)
        XCTAssertEqual(result.status.weekly?.windowMinutes, 10_080)
    }

    func testExpiredCredentialRotatesRefreshTokenBeforeReadingUsage() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiredAccessToken = jwt(["exp": 1_799_999_000])
        let freshAccessToken = jwt(["exp": 1_800_003_600])
        var paths: [String] = []
        CodexStatusURLProtocol.handler = { request in
            paths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/oauth/token":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
                return Self.response(request, json: [
                    "access_token": freshAccessToken,
                    "refresh_token": "refresh-rotated",
                ])
            case "/backend-api/wham/usage":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(freshAccessToken)")
                return Self.response(request, json: [
                    "rate_limit": ["primary_window": ["used_percent": 0]],
                    "rate_limit_reset_credits": ["available_count": 0],
                ])
            case "/backend-api/accounts/check/v4-2023-04-27":
                return Self.response(request, json: [:])
            default:
                XCTFail("意外请求：\(request.url?.absoluteString ?? "nil")")
                return Self.response(request, status: 404, json: [:])
            }
        }

        let result = try await makeService(now: now).refreshStatus(
            authCache: authData(accessToken: expiredAccessToken, refreshToken: "refresh-old"),
            accountID: nil,
            allowCredentialRefresh: true
        )

        XCTAssertEqual(Array(paths.prefix(2)), ["/oauth/token", "/backend-api/wham/usage"])
        let refreshed = try XCTUnwrap(result.refreshedAuthCache)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: refreshed) as? [String: Any])
        let tokens = try XCTUnwrap(document["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["access_token"] as? String, freshAccessToken)
        XCTAssertEqual(tokens["refresh_token"] as? String, "refresh-rotated")
    }

    func testMissingUsageResetCountFallsBackToResetCreditsEndpoint() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let accessToken = jwt(["exp": 1_800_003_600])
        CodexStatusURLProtocol.handler = { request in
            switch request.url?.path {
            case "/backend-api/wham/usage":
                return Self.response(request, json: ["rate_limit": [:]])
            case "/backend-api/wham/rate-limit-reset-credits":
                return Self.response(request, json: ["availableCount": 2])
            case "/backend-api/accounts/check/v4-2023-04-27":
                return Self.response(request, json: [:])
            default:
                XCTFail("意外请求：\(request.url?.absoluteString ?? "nil")")
                return Self.response(request, status: 404, json: [:])
            }
        }

        let result = try await makeService(now: now).refreshStatus(
            authCache: authData(accessToken: accessToken, refreshToken: "refresh-old"),
            accountID: nil,
            allowCredentialRefresh: true
        )

        XCTAssertEqual(result.status.resetCreditsAvailable, 2)
    }

    func testRunningAccountDefersExpiredCredentialRefreshWithoutNetworkRequest() async {
        let expiredAccessToken = jwt(["exp": 1_799_999_000])
        var requested = false
        CodexStatusURLProtocol.handler = { request in
            requested = true
            return Self.response(request, json: [:])
        }

        do {
            _ = try await makeService(now: Date(timeIntervalSince1970: 1_800_000_000)).refreshStatus(
                authCache: authData(accessToken: expiredAccessToken, refreshToken: "refresh-old"),
                accountID: nil,
                allowCredentialRefresh: false
            )
            XCTFail("运行中的当前账号不应争用 refresh token")
        } catch {
            XCTAssertEqual(error as? CodexAccountError, .credentialRefreshDeferred)
        }
        XCTAssertFalse(requested)
    }

    private func makeService(now: Date) -> CodexAccountStatusService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexStatusURLProtocol.self]
        return CodexAccountStatusService(session: URLSession(configuration: configuration), now: { now })
    }

    private func authData(accessToken: String, refreshToken: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "type": "codex",
            "tokens": ["access_token": accessToken, "refresh_token": refreshToken],
        ])
    }

    private func jwt(_ payload: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none"])
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return "\(base64URL(header)).\(base64URL(body)).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        json: [String: Any]
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, try! JSONSerialization.data(withJSONObject: json))
    }
}

private final class CodexStatusURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
