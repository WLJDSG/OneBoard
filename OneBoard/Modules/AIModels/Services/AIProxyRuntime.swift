import Foundation
import Darwin

struct AIProxyRouting: Equatable {
    let baseURL: String
    static let placeholderToken = "PROXY_MANAGED"
}

protocol AIProxyCoordinating: AnyObject {
    func prepare(
        switching profile: AIProviderProfile,
        apiKey: String,
        profiles: [AIProviderProfile],
        activeIDs: [AIClient: UUID],
        secretLoader: (UUID) throws -> String
    ) throws -> AIProxyRouting
    func restore(
        profiles: [AIProviderProfile],
        activeIDs: [AIClient: UUID],
        secretLoader: (UUID) throws -> String
    ) throws
    func stop()
}

final class AIProxyCoordinator: AIProxyCoordinating, @unchecked Sendable {
    static let shared = AIProxyCoordinator()

    private let processURL: URL
    private let lock = NSLock()
    private var process: Process?

    init(processURL: URL = AIProxyCoordinator.defaultProcessURL()) {
        self.processURL = processURL
    }

    func prepare(
        switching profile: AIProviderProfile,
        apiKey: String,
        profiles: [AIProviderProfile],
        activeIDs: [AIClient: UUID],
        secretLoader: (UUID) throws -> String
    ) throws -> AIProxyRouting {
        var selected = activeIDs
        selected[profile.client] = profile.id
        var runtimeProfiles: [(AIProviderProfile, String)] = []
        for client in AIClient.allCases {
            guard let id = selected[client],
                  let selectedProfile = profiles.first(where: { $0.id == id }),
                  selectedProfile.kind == .custom else { continue }
            let secret = id == profile.id ? apiKey : try secretLoader(id)
            runtimeProfiles.append((selectedProfile, secret))
        }
        if !runtimeProfiles.contains(where: { $0.0.id == profile.id }) {
            runtimeProfiles.append((profile, apiKey))
        }

        let payload = try AIProxySnapshotBuilder.makePayload(providers: runtimeProfiles)
        let identities = Dictionary(uniqueKeysWithValues: runtimeProfiles.map { ($0.0.id.uuidString, AIUsageIdentity.make(profile: $0.0, key: $0.1)) })
        let ready = try start(payload: payload, identities: identities)
        let suffix = profile.client == .codex ? "/v1" : ""
        return AIProxyRouting(baseURL: "http://\(ready.address):\(ready.port)\(suffix)")
    }

    func stop() {
        lock.withLock {
            guard let process else { return }
            if process.isRunning {
                OwnedProcessTermination.stop(process)
            }
            self.process = nil
        }
    }

    func restore(
        profiles: [AIProviderProfile],
        activeIDs: [AIClient: UUID],
        secretLoader: (UUID) throws -> String
    ) throws {
        let activeCustomProfiles = activeIDs.compactMap { client, id in
            profiles.first { $0.client == client && $0.id == id && $0.kind == .custom }
        }
        guard let first = activeCustomProfiles.first else {
            stop()
            return
        }
        _ = try prepare(
            switching: first,
            apiKey: secretLoader(first.id),
            profiles: profiles,
            activeIDs: activeIDs,
            secretLoader: secretLoader
        )
    }

    private func start(payload: Data, identities: [String: String]) throws -> ReadyMessage {
        try lock.withLock {
            if let process, process.isRunning {
                OwnedProcessTermination.stop(process)
            }

            guard FileManager.default.isExecutableFile(atPath: processURL.path) else {
                throw AIModelSwitchError.proxyFailure("未找到内置代理：\(processURL.path)")
            }
            let process = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = processURL
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            self.process = process

            try stdin.fileHandleForWriting.write(contentsOf: payload)
            try stdin.fileHandleForWriting.close()

            let line = try readHandshake(from: stdout.fileHandleForReading, process: process)
            guard let data = line.data(using: .utf8),
                  let message = try? JSONDecoder().decode(HandshakeMessage.self, from: data) else {
                OwnedProcessTermination.stop(process)
                throw AIModelSwitchError.proxyFailure("代理启动响应无效")
            }
            guard message.status == "ready", let address = message.address,
                  let port = message.port, port > 0 else {
                OwnedProcessTermination.stop(process)
                throw AIModelSwitchError.proxyFailure(message.message ?? "代理启动失败")
            }
            let reader = AIProxyUsageReader(identities: identities)
            let handle = stdout.fileHandleForReading
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    reader.consume(data)
                }
            }
            // 持续排空 stderr，避免子进程输出填满管道后阻塞。
            let errorHandle = stderr.fileHandleForReading
            DispatchQueue.global(qos: .utility).async {
                while !errorHandle.availableData.isEmpty {}
            }
            return ReadyMessage(address: address, port: port)
        }
    }

    private func readHandshake(from handle: FileHandle, process: Process) throws -> String {
        var data = Data()
        let deadline = Date().addingTimeInterval(10)
        while data.count < 65_536 {
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, poll(&descriptor, 1, Int32(remaining * 1_000)) > 0 else {
                OwnedProcessTermination.stop(process)
                throw AIModelSwitchError.proxyFailure("代理启动超时")
            }
            let chunk = try handle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                if !process.isRunning { break }
                continue
            }
            if chunk[chunk.startIndex] == 0x0A { break }
            data.append(chunk)
        }
        guard let line = String(data: data, encoding: .utf8), !line.isEmpty else {
            throw AIModelSwitchError.proxyFailure("代理进程未返回启动结果")
        }
        return line
    }

    private struct ReadyMessage: Decodable {
        var address: String
        var port: Int
    }

    private struct HandshakeMessage: Decodable {
        var status: String
        var address: String?
        var port: Int?
        var message: String?
    }

    private static func defaultProcessURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["ONEBOARD_AI_PROXY_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("oneboard-ai-proxy")
    }
}

enum AIProxySnapshotBuilder {
    static func makePayload(providers: [(AIProviderProfile, String)]) throws -> Data {
        let runtimeProviders = try providers.map { profile, apiKey -> [String: Any] in
            let validated = try profile.validated()
            return [
                "appType": validated.client.rawValue,
                "current": true,
                "provider": try makeProvider(profile: validated, apiKey: apiKey),
            ]
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "listenPort": 15731,
                "enableLogging": true,
                "providers": runtimeProviders,
            ],
            options: [.sortedKeys]
        )
    }

    private static func makeProvider(profile original: AIProviderProfile, apiKey: String) throws -> [String: Any] {
        var profile = original
        // 模板已确定协议，把解析后的完整地址交给代理，避免兼容前缀再拼一层 v1。
        if profile.presetID != nil, let format = profile.apiFormat, format != .geminiNative,
           let endpoint = AIEndpointResolver.requestURL(baseURL: profile.baseURL, format: format, model: profile.model) {
            profile.baseURL = endpoint.absoluteString
            profile.isFullURL = true
        }
        var settings = jsonObject(profile.runtimeSettingsJSON) ?? defaultSettings(profile: profile)
        inject(apiKey: apiKey, into: &settings, profile: profile)
        var metadata = jsonObject(profile.runtimeMetadataJSON) ?? [:]
        metadata["apiFormat"] = (profile.apiFormat ?? .defaultValue(for: profile.client)).rawValue
        metadata["apiKeyField"] = profile.claudeAPIKeyField.rawValue
        set(profile.isFullURL, key: "isFullUrl", in: &metadata)
        set(profile.customUserAgent, key: "customUserAgent", in: &metadata)
        set(profile.promptCacheKey, key: "promptCacheKey", in: &metadata)
        set(profile.promptCacheRouting?.rawValue, key: "promptCacheRouting", in: &metadata)
        set(profile.impersonateClaudeCode, key: "impersonateClaudeCode", in: &metadata)
        set(profile.maxOutputTokens, key: "maxOutputTokens", in: &metadata)
        set(profile.endpointAutoSelect, key: "endpointAutoSelect", in: &metadata)
        if let endpoints = profile.customEndpoints, !endpoints.isEmpty {
            metadata["custom_endpoints"] = Dictionary(uniqueKeysWithValues: endpoints.map { endpoint in
                (endpoint, ["url": endpoint, "addedAt": 0] as [String: Any])
            })
        }

        var overrides: [String: Any] = [:]
        if let headers = jsonObject(profile.requestHeaderOverridesJSON) { overrides["headers"] = headers }
        if let body = jsonObject(profile.requestBodyOverridesJSON) { overrides["body"] = body }
        if !overrides.isEmpty { metadata["localProxyRequestOverrides"] = overrides }

        return [
            "id": profile.id.uuidString,
            "name": profile.title,
            "settingsConfig": settings,
            "websiteUrl": profile.websiteURL as Any,
            "notes": profile.note as Any,
            "category": "custom",
            "meta": metadata,
            "inFailoverQueue": false,
        ].compactMapValues { value in
            let optional = Mirror(reflecting: value)
            return optional.displayStyle == .optional && optional.children.isEmpty ? nil : value
        }
    }

    private static func defaultSettings(profile: AIProviderProfile) -> [String: Any] {
        switch profile.client {
        case .claude:
            return ["env": claudeEnvironment(profile: profile)]
        case .codex:
            return ["auth": [String: Any](), "config": codexConfig(profile: profile)]
        }
    }

    private static func inject(apiKey: String, into settings: inout [String: Any], profile: AIProviderProfile) {
        switch profile.client {
        case .claude:
            var env = settings["env"] as? [String: Any] ?? [:]
            env["ANTHROPIC_BASE_URL"] = profile.baseURL
            env[profile.claudeAPIKeyField.rawValue] = apiKey
            claudeEnvironment(profile: profile).forEach { env[$0.key] = $0.value }
            settings["env"] = env
        case .codex:
            var auth = settings["auth"] as? [String: Any] ?? [:]
            auth["OPENAI_API_KEY"] = apiKey
            settings["auth"] = auth
            if let config = settings["config"] as? String {
                settings["config"] = updateCodexConfig(config, profile: profile)
            } else {
                settings["config"] = codexConfig(profile: profile)
            }
        }
    }

    private static func updateCodexConfig(_ config: String, profile: AIProviderProfile) -> String {
        let rawLines = config.components(separatedBy: .newlines)
        let selectedProvider = rawLines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model_provider"), let equals = trimmed.firstIndex(of: "=") else { return nil }
            return decodeTOMLString(String(trimmed[trimmed.index(after: equals)...]))
        }.first
        var section = ""
        return rawLines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast())
                return line
            }
            guard let equals = trimmed.firstIndex(of: "=") else { return line }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            if section.isEmpty, key == "model" { return "model = \(tomlString(profile.model))" }
            if key == "base_url",
               section == selectedProvider.map({ "model_providers.\($0)" }) {
                return "base_url = \(tomlString(profile.baseURL))"
            }
            return line
        }.joined(separator: "\n")
    }

    private static func decodeTOMLString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func claudeEnvironment(profile: AIProviderProfile) -> [String: Any] {
        var env: [String: Any] = [
            "ANTHROPIC_BASE_URL": profile.baseURL,
            "ANTHROPIC_MODEL": profile.model,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": profile.claudeHaikuModel ?? profile.model,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": profile.claudeSonnetModel ?? profile.model,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": profile.claudeOpusModel ?? profile.model,
            "ANTHROPIC_DEFAULT_FABLE_MODEL": profile.claudeFableModel ?? profile.claudeOpusModel ?? profile.model,
        ]
        set(profile.claudeHaikuModelName, key: "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME", in: &env)
        set(profile.claudeSonnetModelName, key: "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME", in: &env)
        set(profile.claudeOpusModelName, key: "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME", in: &env)
        set(profile.claudeFableModelName, key: "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME", in: &env)
        set(profile.claudeSubagentModel, key: "CLAUDE_CODE_SUBAGENT_MODEL", in: &env)
        return env
    }

    private static func codexConfig(profile: AIProviderProfile) -> String {
        """
        model_provider = "oneboard-upstream"
        model = \(tomlString(profile.model))

        [model_providers.oneboard-upstream]
        name = \(tomlString(profile.title))
        base_url = \(tomlString(profile.baseURL))
        wire_api = "responses"
        requires_openai_auth = false
        """
    }

    private static func jsonObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func set(_ value: Any?, key: String, in object: inout [String: Any]) {
        if let value { object[key] = value }
        else { object.removeValue(forKey: key) }
    }

    private static func tomlString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}


final class AIProxyUsageReader: @unchecked Sendable {
    private var buffer = Data()
    private let identities: [String: String]
    private let runID = UUID().uuidString
    private let store: AIUsageStore
    init(identities: [String: String], store: AIUsageStore = .shared) {
        self.identities = identities
        self.store = store
    }
    func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["status"] as? String == "usage",
                  let provider = object["providerID"] as? String,
                  let identity = identities[provider],
                  let id = object["id"] as? String,
                  let timestamp = object["timestamp"] as? Double else { continue }
            let event = AIUsageEvent(id: runID + id, credentialID: identity, timestamp: timestamp,
                input: (object["input"] as? NSNumber)?.int64Value ?? 0,
                output: (object["output"] as? NSNumber)?.int64Value ?? 0,
                cacheRead: (object["cacheRead"] as? NSNumber)?.int64Value ?? 0,
                cacheCreation: (object["cacheCreation"] as? NSNumber)?.int64Value ?? 0)
            do { try store.record(event) }
            catch { NSLog("OneBoard: 用量统计保存失败：%@", error.localizedDescription) }
        }
    }
}
