import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct CodexOAuthSession: Equatable, Sendable {
    let id: UUID
    let authorizationURL: URL
    let callbackURL: URL
}

struct CodexOAuthCredential: Equatable, Sendable {
    let email: String
    let accountID: String?
    let planType: String?
    let authCache: Data
}

@MainActor
protocol CodexOAuthAuthorizing: AnyObject {
    func beginAuthorization() async throws -> CodexOAuthSession
    func waitForAuthorization(session: CodexOAuthSession) async throws -> CodexOAuthCredential
    func cancel()
}

@MainActor
protocol CodexOAuthBrowserOpening {
    func open(_ url: URL) -> Bool
}

struct SystemCodexOAuthBrowserOpener: CodexOAuthBrowserOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class SystemCodexOAuthAuthorizer: CodexOAuthAuthorizing {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let authorizationEndpoint = URL(string: "https://auth.openai.com/oauth/authorize")!
    private static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let callbackPort: NWEndpoint.Port = 1455
    private static let scopes = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    private static let originator = "codex_cli_rs"

    private struct PendingAuthorization {
        let session: CodexOAuthSession
        let verifier: String
        let state: String
        var receivedCode: String?
        var continuation: CheckedContinuation<String, Error>?
    }

    private let session: URLSession
    private let callbackQueue = DispatchQueue(label: "com.oneboard.mac.codex-oauth-callback")
    private var listener: NWListener?
    private var pending: PendingAuthorization?
    private var readinessContinuation: CheckedContinuation<UInt16, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func beginAuthorization() async throws -> CodexOAuthSession {
        cancel()

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.callbackPort)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.callbackQueue ?? .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                Task { @MainActor [weak self] in
                    self?.handleCallback(data: data, connection: connection)
                }
            }
        }

        let port = try await waitUntilReady(listener)
        let verifier = try Self.randomToken()
        let state = try Self.randomToken()
        let callbackURL = URL(string: "http://localhost:\(port)/auth/callback")!
        let authorizationURL = try buildAuthorizationURL(
            callbackURL: callbackURL,
            challenge: Self.codeChallenge(for: verifier),
            state: state
        )
        let oauthSession = CodexOAuthSession(
            id: UUID(),
            authorizationURL: authorizationURL,
            callbackURL: callbackURL
        )
        pending = PendingAuthorization(
            session: oauthSession,
            verifier: verifier,
            state: state,
            receivedCode: nil,
            continuation: nil
        )
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.expire(sessionID: oauthSession.id)
        }

        return oauthSession
    }

    func waitForAuthorization(session oauthSession: CodexOAuthSession) async throws -> CodexOAuthCredential {
        guard var current = pending, current.session.id == oauthSession.id else {
            throw CodexAccountError.oauthSessionExpired
        }

        let code: String
        if let receivedCode = current.receivedCode {
            code = receivedCode
        } else {
            code = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    current.continuation = continuation
                    pending = current
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancel() }
            }
        }

        guard let latest = pending, latest.session.id == oauthSession.id else {
            throw CodexAccountError.oauthSessionExpired
        }
        defer { finish() }
        return try await exchangeCode(code, pending: latest)
    }

    func cancel() {
        let continuation = pending?.continuation
        let readinessContinuation = readinessContinuation
        pending = nil
        self.readinessContinuation = nil
        listener?.cancel()
        listener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: CodexAccountError.oauthCancelled)
        readinessContinuation?.resume(throwing: CodexAccountError.oauthCancelled)
    }

    private func finish() {
        pending = nil
        listener?.cancel()
        listener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func expire(sessionID: UUID) {
        guard pending?.session.id == sessionID else { return }
        let continuation = pending?.continuation
        finish()
        continuation?.resume(throwing: CodexAccountError.oauthSessionExpired)
    }

    private func waitUntilReady(_ listener: NWListener) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            readinessContinuation = continuation
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, let listener else { return }
                    self.handleListenerState(state, listener: listener)
                }
            }
            listener.start(queue: callbackQueue)
        }
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        guard let continuation = readinessContinuation else { return }
        switch state {
        case .ready:
            readinessContinuation = nil
            guard let port = listener.port?.rawValue else {
                continuation.resume(throwing: CodexAccountError.oauthCallbackUnavailable)
                return
            }
            continuation.resume(returning: port)
        case .failed:
            readinessContinuation = nil
            continuation.resume(throwing: CodexAccountError.oauthCallbackUnavailable)
        case .cancelled:
            readinessContinuation = nil
            continuation.resume(throwing: CodexAccountError.oauthCancelled)
        default:
            break
        }
    }

    private func handleCallback(data: Data?, connection: NWConnection) {
        guard let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            respond(connection, status: "400 Bad Request", body: "Invalid request")
            return
        }
        let components = requestLine.split(separator: " ")
        guard components.count >= 2,
              let url = URL(string: "http://localhost\(components[1])"),
              url.path == "/auth/callback",
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            respond(connection, status: "404 Not Found", body: "Not Found")
            return
        }

        var values: [String: String] = [:]
        for item in query where values[item.name] == nil {
            values[item.name] = item.value ?? ""
        }
        guard var current = pending, values["state"] == current.state else {
            respond(connection, status: "400 Bad Request", body: "State mismatch")
            return
        }
        if let error = values["error"], !error.isEmpty {
            respond(connection, status: "400 Bad Request", body: "Authorization failed")
            current.continuation?.resume(throwing: CodexAccountError.oauthAuthorizationFailed(error))
            finish()
            return
        }
        guard let code = values["code"], !code.isEmpty else {
            respond(connection, status: "400 Bad Request", body: "Missing code")
            return
        }

        respond(
            connection,
            status: "200 OK",
            body: """
            <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>授权成功</title></head>
            <body style="font-family:-apple-system;padding:48px;text-align:center"><h1>Codex 授权成功</h1><p>可以关闭此页面并返回 OneBoard。</p></body></html>
            """,
            contentType: "text/html; charset=utf-8"
        )
        if let continuation = current.continuation {
            current.continuation = nil
            pending = current
            continuation.resume(returning: code)
        } else {
            current.receivedCode = code
            pending = current
        }
    }

    private func respond(
        _ connection: NWConnection,
        status: String,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func buildAuthorizationURL(callbackURL: URL, challenge: String, state: String) throws -> URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: Self.originator),
        ]
        guard let result = components.url else { throw CodexAccountError.oauthInvalidResponse }
        return result
    }

    private func exchangeCode(_ code: String, pending: PendingAuthorization) async throws -> CodexOAuthCredential {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: pending.session.callbackURL.absoluteString),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code_verifier", value: pending.verifier),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CodexAccountError.oauthTokenExchangeFailed
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !tokens.idToken.isEmpty, !tokens.accessToken.isEmpty else {
            throw CodexAccountError.oauthInvalidResponse
        }
        let idPayload = try Self.jwtPayload(tokens.idToken)
        let accessPayload = try? Self.jwtPayload(tokens.accessToken)
        guard let email = Self.string(in: idPayload, paths: [["email"], ["https://api.openai.com/profile", "email"]]) else {
            throw CodexAccountError.oauthInvalidResponse
        }
        let accountID = Self.string(
            in: accessPayload ?? [:],
            paths: [["https://api.openai.com/auth", "chatgpt_account_id"], ["https://api.openai.com/auth", "account_id"]]
        ) ?? Self.string(in: idPayload, paths: [["https://api.openai.com/auth", "account_id"]])
        let planType = Self.string(in: idPayload, paths: [["https://api.openai.com/auth", "chatgpt_plan_type"]])

        var tokenObject: [String: Any] = [
            "id_token": tokens.idToken,
            "access_token": tokens.accessToken,
            "refresh_token": tokens.refreshToken ?? "",
        ]
        if let accountID { tokenObject["account_id"] = accountID }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let authObject: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "tokens": tokenObject,
            "last_refresh": formatter.string(from: Date()),
            "type": "codex",
        ]
        let authCache = try JSONSerialization.data(withJSONObject: authObject, options: [.sortedKeys])
        return CodexOAuthCredential(email: email, accountID: accountID, planType: planType, authCache: authCache)
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CodexAccountError.oauthCallbackUnavailable
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func jwtPayload(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let data = Data(base64URLEncoded: String(parts[1])),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAccountError.oauthInvalidResponse
        }
        return value
    }

    private static func string(in object: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            var current: Any = object
            for key in path {
                guard let dictionary = current as? [String: Any], let next = dictionary[key] else {
                    current = NSNull()
                    break
                }
                current = next
            }
            if let value = current as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

private struct TokenResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
