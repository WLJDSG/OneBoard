import Foundation
import GRDB

struct CCSwitchImportedProvider {
    var profile: AIProviderProfile
    var apiKey: String?
    var isCurrent: Bool
}

struct CCSwitchImportPayload {
    var providers: [CCSwitchImportedProvider]
    var skippedNames: [String]
}

final class CCSwitchProviderImporter {
    private let databaseURL: URL

    init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cc-switch", isDirectory: true)
        .appendingPathComponent("cc-switch.db")) {
        self.databaseURL = databaseURL
    }

    func load() throws -> CCSwitchImportPayload {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw AIModelSwitchError.importFailure("未找到 \(databaseURL.path)")
        }
        if try databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw AIModelSwitchError.unsafePath(databaseURL.path)
        }

        var configuration = Configuration()
        configuration.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch {
            throw AIModelSwitchError.importFailure("无法只读打开数据库：\(error.localizedDescription)")
        }

        let rows: [Row]
        do {
            rows = try queue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                    SELECT p.id, p.app_type, p.name, p.settings_config, p.website_url, p.notes, p.meta, p.is_current,
                           COALESCE((
                               SELECT json_group_array(e.url)
                               FROM provider_endpoints e
                               WHERE e.provider_id = p.id AND e.app_type = p.app_type
                           ), '[]') AS endpoints_json
                    FROM providers p
                    WHERE app_type IN ('codex', 'claude')
                    ORDER BY p.app_type, COALESCE(p.sort_index, 999999), p.created_at, p.id
                    """
                )
            }
        } catch {
            throw AIModelSwitchError.importFailure("读取供应商失败：\(error.localizedDescription)")
        }

        var providers: [CCSwitchImportedProvider] = []
        var skippedNames: [String] = []
        for row in rows {
            let name: String = row["name"]
            do {
                providers.append(try parse(row: row))
            } catch {
                skippedNames.append(name)
            }
        }
        return CCSwitchImportPayload(providers: providers, skippedNames: skippedNames)
    }

    private func parse(row: Row) throws -> CCSwitchImportedProvider {
        let id: String = row["id"]
        let appType: String = row["app_type"]
        let name: String = row["name"]
        let settingsText: String = row["settings_config"]
        let websiteURL: String? = row["website_url"]
        let notes: String? = row["notes"]
        let metadataText: String = row["meta"]
        let endpointsText: String = row["endpoints_json"]
        let endpoints = Self.stringArray(from: endpointsText)
        let isCurrent: Bool = row["is_current"]
        guard let data = settingsText.data(using: .utf8),
              let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIModelSwitchError.importFailure("\(name) 的配置不是 JSON 对象")
        }

        switch appType {
        case "codex":
            return try parseCodex(
                id: id, name: name, websiteURL: websiteURL, notes: notes,
                settings: settings, metadataText: metadataText, endpoints: endpoints, isCurrent: isCurrent
            )
        case "claude":
            return try parseClaude(
                id: id, name: name, websiteURL: websiteURL, notes: notes,
                settings: settings, metadataText: metadataText, endpoints: endpoints, isCurrent: isCurrent
            )
        default:
            throw AIModelSwitchError.importFailure("不支持 \(appType)")
        }
    }

    private func parseCodex(
        id: String,
        name: String,
        websiteURL: String?,
        notes: String?,
        settings: [String: Any],
        metadataText: String,
        endpoints: [String],
        isCurrent: Bool
    ) throws -> CCSwitchImportedProvider {
        let parsed = Self.parseCodexTOML(settings["config"] as? String ?? "")
        let auth = settings["auth"] as? [String: Any]
        let apiKey = Self.nonEmpty(auth?["OPENAI_API_KEY"] as? String) ?? parsed.apiKey
        let kind: AIProviderKind = parsed.baseURL == nil ? .official : .custom
        let profile = try AIProviderProfile(
            client: .codex,
            kind: kind,
            title: name,
            note: notes,
            websiteURL: websiteURL,
            baseURL: parsed.baseURL ?? "",
            model: parsed.model ?? "",
            apiFormat: Self.apiFormat(from: metadataText, client: .codex),
            isFullURL: Self.metadataBool("isFullUrl", from: metadataText),
            customUserAgent: Self.metadataString("customUserAgent", from: metadataText),
            requestHeaderOverridesJSON: Self.requestOverrideJSON("headers", from: metadataText),
            requestBodyOverridesJSON: Self.requestOverrideJSON("body", from: metadataText),
            promptCacheKey: Self.metadataString("promptCacheKey", from: metadataText),
            promptCacheRouting: Self.promptCacheRouting(from: metadataText),
            impersonateClaudeCode: Self.metadataBool("impersonateClaudeCode", from: metadataText),
            maxOutputTokens: Self.metadataInt("maxOutputTokens", from: metadataText),
            endpointAutoSelect: Self.metadataBool("endpointAutoSelect", from: metadataText),
            customEndpoints: endpoints,
            runtimeSettingsJSON: Self.sanitizedSettingsJSON(settings, client: .codex),
            runtimeMetadataJSON: Self.normalizedJSONObject(metadataText),
            sourceIdentifier: "cc-switch:codex:\(id)"
        ).validated()
        if kind == .custom, apiKey == nil { throw AIModelSwitchError.apiKeyMissing }
        return CCSwitchImportedProvider(profile: profile, apiKey: apiKey, isCurrent: isCurrent)
    }

    private func parseClaude(
        id: String,
        name: String,
        websiteURL: String?,
        notes: String?,
        settings: [String: Any],
        metadataText: String,
        endpoints: [String],
        isCurrent: Bool
    ) throws -> CCSwitchImportedProvider {
        let env = settings["env"] as? [String: Any] ?? [:]
        let baseURL = Self.nonEmpty(env["ANTHROPIC_BASE_URL"] as? String)
        let authToken = Self.nonEmpty(env[ClaudeAPIKeyField.authToken.rawValue] as? String)
        let apiKeyValue = Self.nonEmpty(env[ClaudeAPIKeyField.apiKey.rawValue] as? String)
        let keyField: ClaudeAPIKeyField = authToken != nil ? .authToken : .apiKey
        let apiKey = authToken ?? apiKeyValue
        let haiku = Self.nonEmpty(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] as? String)
        let haikuName = Self.nonEmpty(env["ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] as? String)
        let sonnet = Self.nonEmpty(env["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String)
        let sonnetName = Self.nonEmpty(env["ANTHROPIC_DEFAULT_SONNET_MODEL_NAME"] as? String)
        let opus = Self.nonEmpty(env["ANTHROPIC_DEFAULT_OPUS_MODEL"] as? String)
        let opusName = Self.nonEmpty(env["ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"] as? String)
        let fable = Self.nonEmpty(env["ANTHROPIC_DEFAULT_FABLE_MODEL"] as? String)
        let fableName = Self.nonEmpty(env["ANTHROPIC_DEFAULT_FABLE_MODEL_NAME"] as? String)
        let subagent = Self.nonEmpty(env["CLAUDE_CODE_SUBAGENT_MODEL"] as? String)
        let model = Self.nonEmpty(env["ANTHROPIC_MODEL"] as? String)
            ?? Self.nonEmpty(settings["model"] as? String)
            ?? sonnet ?? opus ?? fable ?? haiku ?? ""
        let kind: AIProviderKind = baseURL == nil && apiKey == nil ? .official : .custom
        let profile = try AIProviderProfile(
            client: .claude,
            kind: kind,
            title: name,
            note: notes,
            websiteURL: websiteURL,
            baseURL: baseURL ?? "",
            model: model,
            apiFormat: Self.apiFormat(from: metadataText, client: .claude),
            isFullURL: Self.metadataBool("isFullUrl", from: metadataText),
            customUserAgent: Self.metadataString("customUserAgent", from: metadataText),
            requestHeaderOverridesJSON: Self.requestOverrideJSON("headers", from: metadataText),
            requestBodyOverridesJSON: Self.requestOverrideJSON("body", from: metadataText),
            promptCacheKey: Self.metadataString("promptCacheKey", from: metadataText),
            endpointAutoSelect: Self.metadataBool("endpointAutoSelect", from: metadataText),
            customEndpoints: endpoints,
            runtimeSettingsJSON: Self.sanitizedSettingsJSON(settings, client: .claude),
            runtimeMetadataJSON: Self.normalizedJSONObject(metadataText),
            claudeAPIKeyField: keyField,
            claudeHaikuModel: haiku,
            claudeHaikuModelName: haikuName,
            claudeSonnetModel: sonnet,
            claudeSonnetModelName: sonnetName,
            claudeOpusModel: opus,
            claudeOpusModelName: opusName,
            claudeFableModel: fable,
            claudeFableModelName: fableName,
            claudeSubagentModel: subagent,
            sourceIdentifier: "cc-switch:claude:\(id)"
        ).validated()
        if kind == .custom, apiKey == nil { throw AIModelSwitchError.apiKeyMissing }
        return CCSwitchImportedProvider(profile: profile, apiKey: apiKey, isCurrent: isCurrent)
    }

    static func parseCodexTOML(_ text: String) -> (model: String?, baseURL: String?, apiKey: String?) {
        var section = ""
        var modelProvider: String?
        var model: String?
        var providerValues: [String: [String: String]] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = decodeTOMLString(String(line[line.index(after: separator)...]))
            guard let value else { continue }
            if section.isEmpty {
                if key == "model" { model = value }
                if key == "model_provider" { modelProvider = value }
            } else if section.hasPrefix("model_providers.") {
                providerValues[section, default: [:]][key] = value
            }
        }

        let selectedSection = modelProvider.map { "model_providers.\($0)" }
        let selected = selectedSection.flatMap { providerValues[$0] }
            ?? providerValues.values.first(where: { $0["base_url"] != nil })
        return (model, nonEmpty(selected?["base_url"]), nonEmpty(selected?["experimental_bearer_token"]))
    }

    private static func decodeTOMLString(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return nil }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func metadataObject(from text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }

    private static func metadataString(_ key: String, from text: String) -> String? {
        nonEmpty(metadataObject(from: text)[key] as? String)
    }

    private static func metadataBool(_ key: String, from text: String) -> Bool? {
        metadataObject(from: text)[key] as? Bool
    }

    private static func metadataInt(_ key: String, from text: String) -> Int? {
        (metadataObject(from: text)[key] as? NSNumber)?.intValue
    }

    private static func apiFormat(from text: String, client: AIClient) -> AIUpstreamAPIFormat {
        metadataString("apiFormat", from: text).flatMap(AIUpstreamAPIFormat.init(rawValue:))
            ?? .defaultValue(for: client)
    }

    private static func promptCacheRouting(from text: String) -> AIPromptCacheRouting? {
        metadataString("promptCacheRouting", from: text).flatMap(AIPromptCacheRouting.init(rawValue:))
    }

    private static func requestOverrideJSON(_ key: String, from text: String) -> String? {
        guard let overrides = metadataObject(from: text)["localProxyRequestOverrides"] as? [String: Any],
              let value = overrides[key],
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return nil }
        return result
    }

    private static func normalizedJSONObject(_ text: String) -> String? {
        let object = metadataObject(from: text)
        guard !object.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stringArray(from text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    private static func sanitizedSettingsJSON(_ settings: [String: Any], client: AIClient) -> String? {
        var sanitized = settings
        switch client {
        case .claude:
            if var env = sanitized["env"] as? [String: Any] {
                ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY"]
                    .forEach { env.removeValue(forKey: $0) }
                sanitized["env"] = env
            }
        case .codex:
            if var auth = sanitized["auth"] as? [String: Any] {
                auth.removeValue(forKey: "OPENAI_API_KEY")
                sanitized["auth"] = auth
            }
            if let config = sanitized["config"] as? String {
                sanitized["config"] = config.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("experimental_bearer_token") }
                    .joined(separator: "\n")
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct CCSwitchImportSummary {
    var importedCount: Int
    var skippedNames: [String]
}

enum OneBoardMaintenance {
    static func importCCSwitch(
        store: AIProviderStore,
        vault: AIProviderSecretVaulting,
        importer: CCSwitchProviderImporter
    ) throws -> CCSwitchImportSummary {
        let payload = try importer.load()
        var profiles = store.profiles
        var importedCount = 0

        for item in payload.providers {
            var profile = item.profile
            if let source = profile.sourceIdentifier,
               let existing = profiles.first(where: { $0.sourceIdentifier == source }) {
                profile.id = existing.id
                profile.createdAt = existing.createdAt
            }
            if profile.kind == .custom, let apiKey = item.apiKey {
                try vault.save(apiKey, for: profile.id)
            }
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
            if item.isCurrent { store.setActiveID(profile.id, for: profile.client) }
            importedCount += 1
        }
        store.profiles = profiles
        return CCSwitchImportSummary(importedCount: importedCount, skippedNames: payload.skippedNames)
    }
}

public enum OneBoardCommandLine {
    public static func importCCSwitch() throws -> String {
        try DatabaseManager.shared.initialize()
        _ = try CodexAuthCredentialStore().read()
        let summary = try OneBoardMaintenance.importCCSwitch(
            store: .shared,
            vault: SQLiteAIProviderSecretVault(),
            importer: CCSwitchProviderImporter()
        )
        let skipped = summary.skippedNames.isEmpty
            ? ""
            : "; skipped=" + summary.skippedNames.joined(separator: ",")
        return "Imported \(summary.importedCount) CC Switch providers\(skipped)"
    }
}
