import Foundation

struct CodexAccountStatusRefreshResult: Equatable, Sendable {
    let status: CodexAccountStatusSnapshot
    let planType: String?
    let refreshedAuthCache: Data?
}

protocol CodexAccountStatusProviding {
    func prepareCredential(_ authCache: Data) async throws -> Data
    func refreshStatus(
        authCache: Data,
        accountID: String?,
        allowCredentialRefresh: Bool
    ) async throws -> CodexAccountStatusRefreshResult
}

final class CodexAccountStatusService: CodexAccountStatusProviding {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let resetCreditsEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    private static let accountCheckEndpoint = URL(string: "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27")!
    private static let subscriptionsEndpoint = URL(string: "https://chatgpt.com/backend-api/subscriptions")!

    private let session: URLSession
    private let now: () -> Date

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func prepareCredential(_ authCache: Data) async throws -> Data {
        var document = try Self.authDocument(from: authCache)
        guard Self.accessTokenNeedsRefresh(in: document, now: now()) else { return authCache }
        try await refreshCredential(document: &document)
        return try Self.encodedAuthDocument(document, refreshedAt: now())
    }

    func refreshStatus(
        authCache: Data,
        accountID: String?,
        allowCredentialRefresh: Bool
    ) async throws -> CodexAccountStatusRefreshResult {
        var document = try Self.authDocument(from: authCache)
        var refreshedAuthCache: Data?

        if Self.accessTokenNeedsRefresh(in: document, now: now()) {
            guard allowCredentialRefresh else { throw CodexAccountError.credentialRefreshDeferred }
            try await refreshCredential(document: &document)
            refreshedAuthCache = try Self.encodedAuthDocument(document, refreshedAt: now())
        }

        var response = try await fetchUsage(document: document, accountID: accountID)
        if response.statusCode == 401 || response.statusCode == 403 {
            guard allowCredentialRefresh else { throw CodexAccountError.credentialRefreshDeferred }
            try await refreshCredential(document: &document)
            refreshedAuthCache = try Self.encodedAuthDocument(document, refreshedAt: now())
            response = try await fetchUsage(document: document, accountID: accountID)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CodexAccountError.accountStatusUnavailable("服务返回 HTTP \(response.statusCode)")
        }

        let payload = try Self.jsonObject(from: response.data)
        let rateLimit = payload["rate_limit"] as? [String: Any]
        let primaryWindow = Self.window(from: rateLimit?["primary_window"], now: now())
        let secondaryWindow = Self.window(from: rateLimit?["secondary_window"], now: now())
        let windows = [primaryWindow, secondaryWindow].compactMap { $0 }
        let fiveHour = windows.first { ($0.windowMinutes ?? 0) > 0 && ($0.windowMinutes ?? 0) <= 24 * 60 }
            ?? (primaryWindow?.windowMinutes == nil ? primaryWindow : nil)
        let weekly = windows.first { ($0.windowMinutes ?? 0) > 24 * 60 }
            ?? (secondaryWindow?.windowMinutes == nil ? secondaryWindow : nil)
        var usageResetCount = Self.integer(
            in: payload["rate_limit_reset_credits"],
            keys: ["available_count", "availableCount"]
        )
        if usageResetCount == nil,
           let resetPayload = try? await fetchResetCredits(document: document, accountID: accountID) {
            usageResetCount = Self.resetCreditsCount(in: resetPayload)
        }
        var planType = Self.string(in: payload, keys: ["plan_type"])
        var subscriptionExpiry = Self.subscriptionExpiry(from: document)

        if let subscription = try? await fetchSubscription(
            document: document,
            accountID: accountID
        ) {
            planType = subscription.planType ?? planType
            subscriptionExpiry = subscription.expiresAt ?? subscriptionExpiry
        }

        let status = CodexAccountStatusSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            resetCreditsAvailable: usageResetCount,
            subscriptionActiveUntil: subscriptionExpiry,
            fetchedAt: now()
        )
        return CodexAccountStatusRefreshResult(
            status: status,
            planType: planType,
            refreshedAuthCache: refreshedAuthCache
        )
    }

    private func refreshCredential(document: inout [String: Any]) async throws {
        guard var tokens = document["tokens"] as? [String: Any],
              let refreshToken = Self.nonEmptyString(tokens["refresh_token"]) else {
            throw CodexAccountError.credentialRefreshFailed("缺少 refresh token，请重新授权")
        }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: Self.clientID),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexAccountError.credentialRefreshFailed("未收到有效响应")
        }
        guard (200..<300).contains(http.statusCode),
              let refreshed = try? Self.jsonObject(from: data),
              let accessToken = Self.nonEmptyString(refreshed["access_token"]) else {
            throw CodexAccountError.credentialRefreshFailed("服务返回 HTTP \(http.statusCode)，请重新授权")
        }

        tokens["access_token"] = accessToken
        if let idToken = Self.nonEmptyString(refreshed["id_token"]) { tokens["id_token"] = idToken }
        if let rotatedRefreshToken = Self.nonEmptyString(refreshed["refresh_token"]) {
            tokens["refresh_token"] = rotatedRefreshToken
        }
        document["tokens"] = tokens
    }

    private func fetchUsage(document: [String: Any], accountID: String?) async throws -> HTTPResult {
        try await sendAuthenticatedRequest(
            url: Self.usageEndpoint,
            document: document,
            accountID: accountID
        )
    }

    private func fetchResetCredits(document: [String: Any], accountID: String?) async throws -> Any {
        let response = try await sendAuthenticatedRequest(
            url: Self.resetCreditsEndpoint,
            document: document,
            accountID: accountID
        )
        guard (200..<300).contains(response.statusCode) else {
            throw CodexAccountError.accountStatusUnavailable("重置次数接口不可用")
        }
        return try JSONSerialization.jsonObject(with: response.data)
    }

    private func fetchSubscription(
        document: [String: Any],
        accountID: String?
    ) async throws -> SubscriptionSnapshot {
        var components = URLComponents(url: Self.accountCheckEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timezone_offset_min", value: String(TimeZone.current.secondsFromGMT() / 60)),
        ]
        let accountResponse = try await sendAuthenticatedRequest(
            url: components.url!,
            document: document,
            accountID: nil,
            targetPath: "/backend-api/accounts/check/v4-2023-04-27"
        )
        guard (200..<300).contains(accountResponse.statusCode) else { throw CodexAccountError.accountStatusUnavailable("订阅接口不可用") }
        let accountPayload = try JSONSerialization.jsonObject(with: accountResponse.data)
        var snapshot = Self.findSubscription(in: accountPayload, matching: accountID)
        if snapshot.expiresAt != nil { return snapshot }

        let resolvedAccountID = snapshot.accountID ?? accountID ?? Self.accountID(from: document)
        guard let resolvedAccountID else { return snapshot }
        var subscriptionComponents = URLComponents(url: Self.subscriptionsEndpoint, resolvingAgainstBaseURL: false)!
        subscriptionComponents.queryItems = [URLQueryItem(name: "account_id", value: resolvedAccountID)]
        let response = try await sendAuthenticatedRequest(
            url: subscriptionComponents.url!,
            document: document,
            accountID: nil,
            targetPath: "/backend-api/subscriptions"
        )
        guard (200..<300).contains(response.statusCode) else { return snapshot }
        let payload = try JSONSerialization.jsonObject(with: response.data)
        let fallback = Self.findSubscription(in: payload, matching: resolvedAccountID)
        snapshot = SubscriptionSnapshot(
            accountID: fallback.accountID ?? snapshot.accountID,
            planType: fallback.planType ?? snapshot.planType,
            expiresAt: fallback.expiresAt ?? snapshot.expiresAt
        )
        return snapshot
    }

    private func sendAuthenticatedRequest(
        url: URL,
        document: [String: Any],
        accountID: String?,
        targetPath: String? = nil
    ) async throws -> HTTPResult {
        guard let tokens = document["tokens"] as? [String: Any],
              let accessToken = Self.nonEmptyString(tokens["access_token"]) else {
            throw CodexAccountError.invalidAuthCache
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        if let targetPath {
            request.setValue(targetPath, forHTTPHeaderField: "x-openai-target-path")
            request.setValue(targetPath, forHTTPHeaderField: "x-openai-target-route")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CodexAccountError.accountStatusUnavailable("未收到有效响应")
            }
            return HTTPResult(statusCode: http.statusCode, data: data)
        } catch let error as CodexAccountError {
            throw error
        } catch {
            throw CodexAccountError.accountStatusUnavailable(error.localizedDescription)
        }
    }

    private static func authDocument(from data: Data) throws -> [String: Any] {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["tokens"] is [String: Any] else {
            throw CodexAccountError.invalidAuthCache
        }
        return document
    }

    private static func encodedAuthDocument(_ document: [String: Any], refreshedAt: Date) throws -> Data {
        var updated = document
        updated["last_refresh"] = ISO8601DateFormatter().string(from: refreshedAt)
        return try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys])
    }

    private static func accessTokenNeedsRefresh(in document: [String: Any], now: Date) -> Bool {
        guard let tokens = document["tokens"] as? [String: Any],
              let token = nonEmptyString(tokens["access_token"]) else { return true }
        guard let payload = jwtPayload(token), let expiration = number(payload["exp"]) else {
            return false
        }
        return Date(timeIntervalSince1970: expiration) <= now.addingTimeInterval(300)
    }

    private static func window(from value: Any?, now: Date) -> CodexUsageWindowSnapshot? {
        guard let object = value as? [String: Any],
              let used = integer(object["used_percent"]), (0...100).contains(used) else { return nil }
        let resetAt: Date?
        if let timestamp = number(object["reset_at"]) {
            resetAt = Date(timeIntervalSince1970: timestamp)
        } else if let seconds = number(object["reset_after_seconds"]), seconds >= 0 {
            resetAt = now.addingTimeInterval(seconds)
        } else {
            resetAt = nil
        }
        let seconds = integer(object["limit_window_seconds"])
        return CodexUsageWindowSnapshot(
            remainingPercent: 100 - used,
            resetAt: resetAt,
            windowMinutes: seconds.map { max(1, ($0 + 59) / 60) }
        )
    }

    private static func subscriptionExpiry(from document: [String: Any]) -> Date? {
        guard let tokens = document["tokens"] as? [String: Any],
              let idToken = nonEmptyString(tokens["id_token"]),
              let payload = jwtPayload(idToken),
              let auth = payload["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return date(auth["chatgpt_subscription_active_until"])
    }

    private static func accountID(from document: [String: Any]) -> String? {
        guard let tokens = document["tokens"] as? [String: Any] else { return nil }
        if let accountID = nonEmptyString(tokens["account_id"]) { return accountID }
        guard let accessToken = nonEmptyString(tokens["access_token"]),
              let payload = jwtPayload(accessToken),
              let auth = payload["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return nonEmptyString(auth["chatgpt_account_id"]) ?? nonEmptyString(auth["account_id"])
    }

    private static func findSubscription(in value: Any, matching accountID: String?) -> SubscriptionSnapshot {
        var candidates: [SubscriptionSnapshot] = []
        collectSubscriptions(in: value, into: &candidates)
        return candidates.first(where: { accountID != nil && $0.accountID == accountID })
            ?? candidates.first(where: { $0.expiresAt != nil })
            ?? candidates.first
            ?? SubscriptionSnapshot(accountID: nil, planType: nil, expiresAt: nil)
    }

    private static func collectSubscriptions(in value: Any, into result: inout [SubscriptionSnapshot]) {
        if let object = value as? [String: Any] {
            let snapshot = SubscriptionSnapshot(
                accountID: string(in: object, keys: ["account_id", "id"]),
                planType: string(in: object, keys: ["plan_type", "subscription_plan"]),
                expiresAt: date(object["active_until"] ?? object["expires_at"] ?? object["subscription_active_until"])
            )
            if snapshot.accountID != nil || snapshot.planType != nil || snapshot.expiresAt != nil {
                result.append(snapshot)
            }
            for child in object.values { collectSubscriptions(in: child, into: &result) }
        } else if let array = value as? [Any] {
            for child in array { collectSubscriptions(in: child, into: &result) }
        }
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAccountError.accountStatusUnavailable("响应格式无效")
        }
        return value
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let data = base64URLData(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return payload
    }

    private static func base64URLData(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = nonEmptyString(object[key]) { return value }
        }
        return nil
    }

    private static func integer(in value: Any?, keys: [String]) -> Int? {
        guard let object = value as? [String: Any] else { return nil }
        for key in keys {
            if let result = integer(object[key]) { return result }
        }
        return nil
    }

    private static func resetCreditsCount(in value: Any) -> Int? {
        if let object = value as? [String: Any] {
            if let count = integer(in: object, keys: ["available_count", "availableCount"]) {
                return count
            }
            if let data = object["data"] { return resetCreditsCount(in: data) }
            if let credits = object["credits"] as? [[String: Any]] {
                return credits.filter { credit in
                    let status = nonEmptyString(credit["status"])?.lowercased()
                    return status == nil || status == "available"
                }.count
            }
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return TimeInterval(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = number(value) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        guard let raw = nonEmptyString(value) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

private struct HTTPResult {
    let statusCode: Int
    let data: Data
}

private struct SubscriptionSnapshot {
    let accountID: String?
    let planType: String?
    let expiresAt: Date?
}
