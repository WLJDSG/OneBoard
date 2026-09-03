import Foundation
import XCTest
@testable import OneBoardKit

@MainActor
final class CodexOAuthAuthorizerTests: XCTestCase {
    override func tearDown() {
        OAuthTokenURLProtocol.handler = nil
        super.tearDown()
    }

    func testOAuthFlowBuildsOfficialURLReceivesCallbackAndCreatesCodexAuthCache() async throws {
        let idToken = jwt([
            "email": "work@example.com",
            "https://api.openai.com/auth": ["chatgpt_plan_type": "plus"],
        ])
        let accessToken = jwt([
            "https://api.openai.com/auth": ["chatgpt_account_id": "account-123"],
        ])
        let tokenData = try JSONSerialization.data(withJSONObject: [
            "id_token": idToken,
            "access_token": accessToken,
            "refresh_token": "refresh-123",
        ])

        OAuthTokenURLProtocol.handler = { request in
            guard request.url?.absoluteString == "https://auth.openai.com/oauth/token",
                  request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded" else {
                throw CodexAccountError.oauthTokenExchangeFailed
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, tokenData)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthTokenURLProtocol.self]
        let authorizer = SystemCodexOAuthAuthorizer(
            session: URLSession(configuration: configuration)
        )
        defer { authorizer.cancel() }

        let oauthSession = try await authorizer.beginAuthorization()
        let authorizationComponents = try XCTUnwrap(
            URLComponents(url: oauthSession.authorizationURL, resolvingAgainstBaseURL: false)
        )
        let authorizationItems = dictionary(authorizationComponents.queryItems)
        XCTAssertEqual(authorizationComponents.host, "auth.openai.com")
        XCTAssertEqual(authorizationComponents.path, "/oauth/authorize")
        XCTAssertEqual(authorizationItems["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(authorizationItems["code_challenge_method"], "S256")
        XCTAssertEqual(authorizationItems["redirect_uri"], oauthSession.callbackURL.absoluteString)
        XCTAssertEqual(oauthSession.callbackURL.absoluteString, "http://localhost:1455/auth/callback")
        XCTAssertEqual(authorizationItems["originator"], "codex_cli_rs")
        XCTAssertNil(authorizationItems["codex_app_version"])
        XCTAssertNil(authorizationItems["source_surface_stable_id"])
        XCTAssertNil(authorizationItems["codex_origin_stable_id"])
        XCTAssertFalse(try XCTUnwrap(authorizationItems["code_challenge"]).isEmpty)

        var callbackComponents = try XCTUnwrap(
            URLComponents(url: oauthSession.callbackURL, resolvingAgainstBaseURL: false)
        )
        callbackComponents.queryItems = [
            URLQueryItem(name: "code", value: "callback-code"),
            URLQueryItem(name: "state", value: try XCTUnwrap(authorizationItems["state"])),
        ]
        let (_, callbackResponse) = try await URLSession.shared.data(from: try XCTUnwrap(callbackComponents.url))
        XCTAssertEqual((callbackResponse as? HTTPURLResponse)?.statusCode, 200)

        let credential = try await authorizer.waitForAuthorization(session: oauthSession)
        XCTAssertEqual(credential.email, "work@example.com")
        XCTAssertEqual(credential.accountID, "account-123")
        XCTAssertEqual(credential.planType, "plus")

        let auth = try XCTUnwrap(
            JSONSerialization.jsonObject(with: credential.authCache) as? [String: Any]
        )
        XCTAssertEqual(auth["type"] as? String, "codex")
        let tokens = try XCTUnwrap(auth["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["id_token"] as? String, idToken)
        XCTAssertEqual(tokens["access_token"] as? String, accessToken)
        XCTAssertEqual(tokens["refresh_token"] as? String, "refresh-123")
        XCTAssertEqual(tokens["account_id"] as? String, "account-123")
    }

    private func dictionary(_ items: [URLQueryItem]?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (items ?? []).map { ($0.name, $0.value ?? "") })
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
}

private final class OAuthTokenURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw CodexAccountError.oauthTokenExchangeFailed }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
