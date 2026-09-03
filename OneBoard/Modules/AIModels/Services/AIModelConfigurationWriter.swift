import Foundation

protocol AIModelConfigurationWriting {
    func apply(_ profile: AIProviderProfile, apiKey: String?) throws
    func restoreBackup(for client: AIClient) throws
}

final class AIModelConfigurationWriter: AIModelConfigurationWriting {
    private let codexConfigURL: URL
    private let claudeSettingsURL: URL
    private let fileManager: FileManager

    init(
        codexConfigURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml"),
        claudeSettingsURL: URL = AIModelConfigurationWriter.defaultClaudeSettingsURL(),
        fileManager: FileManager = .default
    ) {
        self.codexConfigURL = codexConfigURL
        self.claudeSettingsURL = claudeSettingsURL
        self.fileManager = fileManager
    }

    func apply(_ profile: AIProviderProfile, apiKey: String?) throws {
        let profile = try profile.validated()
        if profile.kind == .custom, apiKey?.isEmpty != false { throw AIModelSwitchError.apiKeyMissing }
        switch profile.client {
        case .codex: try applyCodex(profile, apiKey: apiKey)
        case .claude: try applyClaude(profile, apiKey: apiKey)
        }
    }

    func restoreBackup(for client: AIClient) throws {
        let target = client == .codex ? codexConfigURL : claudeSettingsURL
        let backup = backupURL(for: target)
        guard fileManager.fileExists(atPath: backup.path) else {
            throw AIModelSwitchError.backupMissing(backup.path)
        }
        try validateSafePath(backup)
        try atomicWrite(try Data(contentsOf: backup), to: target)
    }

    private func applyCodex(_ profile: AIProviderProfile, apiKey: String?) throws {
        let existing = try readTextIfPresent(codexConfigURL) ?? ""
        try createBackupIfNeeded(for: codexConfigURL, data: Data(existing.utf8))
        let output = Self.rewriteCodexConfig(existing, profile: profile, apiKey: apiKey)
        try atomicWrite(Data(output.utf8), to: codexConfigURL)
    }

    private func applyClaude(_ profile: AIProviderProfile, apiKey: String?) throws {
        let existingData = try readDataIfPresent(claudeSettingsURL)
        let root: [String: Any]
        if let existingData {
            guard let object = try? JSONSerialization.jsonObject(with: existingData),
                  let dictionary = object as? [String: Any] else {
                throw AIModelSwitchError.invalidConfiguration("Claude settings.json 必须是 JSON 对象")
            }
            root = dictionary
        } else {
            root = [:]
        }
        try createBackupIfNeeded(for: claudeSettingsURL, data: existingData ?? Data("{}\n".utf8))

        var updated = root
        if root["env"] != nil, !(root["env"] is [String: Any]) {
            throw AIModelSwitchError.invalidConfiguration("Claude settings.json 的 env 必须是 JSON 对象")
        }
        var env = root["env"] as? [String: Any] ?? [:]
        Self.managedClaudeEnvironmentKeys.forEach { env.removeValue(forKey: $0) }
        env["ANTHROPIC_MODEL"] = profile.model
        env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = profile.claudeHaikuModel ?? profile.model
        env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = profile.claudeSonnetModel ?? profile.model
        env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = profile.claudeOpusModel ?? profile.model
        env["ANTHROPIC_DEFAULT_FABLE_MODEL"] = profile.claudeFableModel
            ?? profile.claudeOpusModel
            ?? profile.model
        Self.setIfPresent(profile.claudeHaikuModelName, key: "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME", in: &env)
        Self.setIfPresent(profile.claudeSonnetModelName, key: "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME", in: &env)
        Self.setIfPresent(profile.claudeOpusModelName, key: "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME", in: &env)
        Self.setIfPresent(profile.claudeFableModelName, key: "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME", in: &env)
        Self.setIfPresent(profile.claudeSubagentModel, key: "CLAUDE_CODE_SUBAGENT_MODEL", in: &env)
        if profile.kind == .custom, let apiKey {
            env["ANTHROPIC_BASE_URL"] = profile.baseURL
            env[profile.claudeAPIKeyField.rawValue] = apiKey
        }
        updated["env"] = env

        let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(data + Data([0x0A]), to: claudeSettingsURL)
    }

    private static func setIfPresent(_ value: String?, key: String, in environment: inout [String: Any]) {
        if let value { environment[key] = value }
    }

    static func rewriteCodexConfig(_ existing: String, profile: AIProviderProfile, apiKey: String?) -> String {
        var lines: [String] = []
        var inManagedTable = false
        var reachedFirstTable = false

        for line in existing.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if trimmed == "[model_providers.oneboard]" {
                    inManagedTable = true
                    reachedFirstTable = true
                    continue
                }
                inManagedTable = false
                reachedFirstTable = true
            }
            if inManagedTable { continue }
            if !reachedFirstTable,
               Self.isTopLevelAssignment(trimmed, key: "model") ||
                (!reachedFirstTable && Self.isTopLevelAssignment(trimmed, key: "model_provider")) {
                continue
            }
            lines.append(line)
        }

        while lines.last?.isEmpty == true { lines.removeLast() }
        var prefix = ["model = \(tomlString(profile.model))"]
        if profile.kind == .custom { prefix.insert("model_provider = \"oneboard\"", at: 0) }
        var output = prefix.joined(separator: "\n") + "\n"
        if !lines.isEmpty { output += "\n" + lines.joined(separator: "\n") + "\n" }
        if profile.kind == .custom, let apiKey {
            output += "\n[model_providers.oneboard]\n"
            output += "name = \(tomlString(profile.title))\n"
            output += "base_url = \(tomlString(profile.baseURL))\n"
            output += "wire_api = \"responses\"\n"
            output += "requires_openai_auth = false\n"
            output += "experimental_bearer_token = \(tomlString(apiKey))\n"
        }
        return output
    }

    private static func isTopLevelAssignment(_ line: String, key: String) -> Bool {
        guard let equals = line.firstIndex(of: "=") else { return false }
        return line[..<equals].trimmingCharacters(in: .whitespaces) == key
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private func readTextIfPresent(_ url: URL) throws -> String? {
        guard let data = try readDataIfPresent(url) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AIModelSwitchError.invalidConfiguration("\(url.path) 不是 UTF-8 文本")
        }
        return text
    }

    private func readDataIfPresent(_ url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try validateSafePath(url)
        return try Data(contentsOf: url)
    }

    private func createBackupIfNeeded(for url: URL, data: Data) throws {
        let backup = backupURL(for: url)
        guard !fileManager.fileExists(atPath: backup.path) else { return }
        try atomicWrite(data, to: backup)
    }

    private func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("oneboard-backup")
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try validateSafePath(url)
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func validateSafePath(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw AIModelSwitchError.unsafePath(url.path)
        }
    }

    private static func defaultClaudeSettingsURL() -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        let settings = directory.appendingPathComponent("settings.json")
        let legacy = directory.appendingPathComponent("claude.json")
        if FileManager.default.fileExists(atPath: settings.path) { return settings }
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return settings
    }

    private static let managedClaudeEnvironmentKeys: Set<String> = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
        "ANTHROPIC_DEFAULT_FABLE_MODEL",
        "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME",
        "CLAUDE_CODE_SUBAGENT_MODEL",
    ]
}
