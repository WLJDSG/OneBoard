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
                    SELECT id, app_type, name, settings_config, is_current
                    FROM providers
                    WHERE app_type IN ('codex', 'claude')
                    ORDER BY app_type, COALESCE(sort_index, 999999), created_at, id
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
        let isCurrent: Bool = row["is_current"]
        guard let data = settingsText.data(using: .utf8),
              let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIModelSwitchError.importFailure("\(name) 的配置不是 JSON 对象")
        }

        switch appType {
        case "codex":
            return try parseCodex(id: id, name: name, settings: settings, isCurrent: isCurrent)
        case "claude":
            return try parseClaude(id: id, name: name, settings: settings, isCurrent: isCurrent)
        default:
            throw AIModelSwitchError.importFailure("不支持 \(appType)")
        }
    }

    private func parseCodex(
        id: String,
        name: String,
        settings: [String: Any],
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
            baseURL: parsed.baseURL ?? "",
            model: parsed.model ?? "",
            sourceIdentifier: "cc-switch:codex:\(id)"
        ).validated()
        if kind == .custom, apiKey == nil { throw AIModelSwitchError.apiKeyMissing }
        return CCSwitchImportedProvider(profile: profile, apiKey: apiKey, isCurrent: isCurrent)
    }

    private func parseClaude(
        id: String,
        name: String,
        settings: [String: Any],
        isCurrent: Bool
    ) throws -> CCSwitchImportedProvider {
        let env = settings["env"] as? [String: Any] ?? [:]
        let baseURL = Self.nonEmpty(env["ANTHROPIC_BASE_URL"] as? String)
        let authToken = Self.nonEmpty(env[ClaudeAPIKeyField.authToken.rawValue] as? String)
        let apiKeyValue = Self.nonEmpty(env[ClaudeAPIKeyField.apiKey.rawValue] as? String)
        let keyField: ClaudeAPIKeyField = authToken != nil ? .authToken : .apiKey
        let apiKey = authToken ?? apiKeyValue
        let haiku = Self.nonEmpty(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] as? String)
        let sonnet = Self.nonEmpty(env["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String)
        let opus = Self.nonEmpty(env["ANTHROPIC_DEFAULT_OPUS_MODEL"] as? String)
        let model = Self.nonEmpty(env["ANTHROPIC_MODEL"] as? String)
            ?? Self.nonEmpty(settings["model"] as? String)
            ?? sonnet ?? opus ?? haiku ?? ""
        let kind: AIProviderKind = baseURL == nil && apiKey == nil ? .official : .custom
        let profile = try AIProviderProfile(
            client: .claude,
            kind: kind,
            title: name,
            baseURL: baseURL ?? "",
            model: model,
            claudeAPIKeyField: keyField,
            claudeHaikuModel: haiku,
            claudeSonnetModel: sonnet,
            claudeOpusModel: opus,
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
