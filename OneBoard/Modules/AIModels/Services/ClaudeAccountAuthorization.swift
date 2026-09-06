import AppKit
import CryptoKit
import Foundation
import Security

struct ClaudeAccountCredential: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

/// Claude Code 官方浏览器授权；参照 cockpit-tools 的 PKCE / 授权码回填流程。
/// 待授权状态只在内存中，持久凭据保存到 OneBoard SQLite。
@MainActor
final class ClaudeAccountAuthorization: ObservableObject {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirect = "https://platform.claude.com/oauth/code/callback"
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    @Published private(set) var authorizationURL: URL?
    private var verifier = ""
    private var state = ""
    private var startedAt = Date.distantPast
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func begin() throws {
        verifier = try Self.randomToken(); state = try Self.randomToken(); startedAt = Date()
        var url = URLComponents(string: "https://claude.com/cai/oauth/authorize")!
        let challenge = Self.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
        url.queryItems = ["code": "true", "client_id": Self.clientID, "response_type": "code",
            "redirect_uri": Self.redirect, "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload",
            "code_challenge": challenge, "code_challenge_method": "S256", "state": state]
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        authorizationURL = url.url
    }

    func complete(_ input: String) async throws -> ClaudeAccountCredential {
        guard !verifier.isEmpty, Date().timeIntervalSince(startedAt) < 600 else {
            throw AIProviderQuotaError("授权已过期，请重新打开浏览器授权")
        }
        let code = try Self.authorizationCode(input, expectedState: state)
        let expected = state
        let credential = try await exchange(["grant_type": "authorization_code", "client_id": Self.clientID,
            "code": code, "redirect_uri": Self.redirect, "code_verifier": verifier, "state": state])
        guard state == expected else { throw CancellationError() }
        cancel()
        return credential
    }

    func cancel() { verifier = ""; state = ""; authorizationURL = nil }

    static func authorizationCode(_ input: String, expectedState: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let code: String; let state: String?
        if value.hasPrefix("https://") || value.hasPrefix("http://") {
            guard let url = URLComponents(string: value),
                  url.scheme == "https", url.host == "platform.claude.com", url.path == "/oauth/code/callback" else {
                throw AIProviderQuotaError("请粘贴授权完成页返回的授权码或回调地址")
            }
            code = url.queryItems?.first { $0.name == "code" }?.value ?? ""
            state = url.queryItems?.first { $0.name == "state" }?.value
        } else {
            let parts = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            code = String(parts.first ?? "")
            state = parts.count == 2 ? String(parts[1]) : nil
        }
        guard !code.isEmpty, !code.contains(where: { $0.isWhitespace }),
              state == nil || state == expectedState else { throw AIProviderQuotaError("授权码无效或不属于本次授权") }
        return code
    }

    func refreshed(_ credential: ClaudeAccountCredential) async throws -> ClaudeAccountCredential {
        guard credential.expiresAt.timeIntervalSinceNow < 300 else { return credential }
        guard let refresh = credential.refreshToken, !refresh.isEmpty else { throw AIProviderQuotaError("Claude 登录已过期，请重新授权") }
        var result = try await exchange(["grant_type": "refresh_token", "client_id": Self.clientID, "refresh_token": refresh])
        if result.refreshToken == nil { result.refreshToken = refresh }
        return result
    }

    private func exchange(_ body: [String: String]) async throws -> ClaudeAccountCredential {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIProviderQuotaError("Claude 授权失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），请重新授权")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = root["access_token"] as? String, !token.isEmpty,
              let expires = root["expires_in"] as? Double, expires > 0 else {
            throw AIProviderQuotaError("Claude 授权响应缺少有效凭据")
        }
        return ClaudeAccountCredential(accessToken: token, refreshToken: root["refresh_token"] as? String,
                                       expiresAt: Date().addingTimeInterval(expires))
    }

    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AIProviderQuotaError("无法生成安全授权参数")
        }
        return base64(Data(bytes))
    }
}

struct ClaudeAccountCredentialStore {
    var repository: PrivateDataRepository = .shared
    func save(_ credential: ClaudeAccountCredential, id: UUID) throws {
        try repository.save(JSONEncoder().encode(credential), namespace: "claude_account_oauth", recordID: id.uuidString)
    }
    func load(id: UUID) throws -> ClaudeAccountCredential? {
        guard let data = try repository.load(namespace: "claude_account_oauth", recordID: id.uuidString) else { return nil }
        return try JSONDecoder().decode(ClaudeAccountCredential.self, from: data)
    }
    func delete(id: UUID) throws { try repository.delete(namespace: "claude_account_oauth", recordID: id.uuidString) }
}
