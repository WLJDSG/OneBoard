import Foundation

@MainActor
final class AIModelSwitcherViewModel: ObservableObject {
    static let shared = AIModelSwitcherViewModel()

    @Published private(set) var profiles: [AIProviderProfile] = []
    @Published private(set) var isSwitching = false
    @Published var statusMessage: String?

    private let store: AIProviderStore
    private let vault: AIProviderSecretVaulting
    private let writer: AIModelConfigurationWriting
    private let ccSwitchImporter: CCSwitchProviderImporter

    init(
        store: AIProviderStore = .shared,
        vault: AIProviderSecretVaulting = SQLiteAIProviderSecretVault(),
        writer: AIModelConfigurationWriting = AIModelConfigurationWriter(),
        ccSwitchImporter: CCSwitchProviderImporter = CCSwitchProviderImporter()
    ) {
        self.store = store
        self.vault = vault
        self.writer = writer
        self.ccSwitchImporter = ccSwitchImporter
        reload()
    }

    func profiles(for client: AIClient) -> [AIProviderProfile] {
        profiles.filter { $0.client == client }
    }

    func activeID(for client: AIClient) -> UUID? {
        store.activeID(for: client)
    }

    func hasSavedAPIKey(for profile: AIProviderProfile) -> Bool {
        vault.contains(profileID: profile.id)
    }

    func save(_ profile: AIProviderProfile, apiKey: String?) throws {
        var validated = try profile.validated()
        validated.updatedAt = Date()
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if validated.kind == .custom {
            guard !trimmedKey.isEmpty || vault.contains(profileID: validated.id) else {
                throw AIModelSwitchError.apiKeyMissing
            }
            if !trimmedKey.isEmpty { try vault.save(trimmedKey, for: validated.id) }
        } else {
            try vault.delete(for: validated.id)
        }
        store.save(validated)
        reload()
        statusMessage = "已保存 \(validated.title)"
    }

    func delete(_ profile: AIProviderProfile) {
        do {
            try vault.delete(for: profile.id)
            store.delete(id: profile.id)
            reload()
            statusMessage = "已删除 \(profile.title)；当前活动配置文件未改动"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func switchProfile(id: UUID) -> String {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            let message = AIModelSwitchError.profileNotFound.localizedDescription
            statusMessage = message
            return message
        }
        isSwitching = true
        defer { isSwitching = false }
        do {
            let apiKey = profile.kind == .custom ? try vault.load(for: profile.id) : nil
            try writer.apply(profile, apiKey: apiKey)
            store.setActiveID(profile.id, for: profile.client)
            let message = "已切换 \(profile.client.title) 到 \(profile.title) / \(profile.model)；新会话生效"
            statusMessage = message
            return message
        } catch {
            let message = error.localizedDescription
            statusMessage = message
            return message
        }
    }

    func restoreBackup(for client: AIClient) {
        do {
            try writer.restoreBackup(for: client)
            store.setActiveID(nil, for: client)
            statusMessage = "已恢复 \(client.title) 的 OneBoard 初次切换前备份"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importFromCCSwitch() {
        do {
            let summary = try OneBoardMaintenance.importCCSwitch(
                store: store,
                vault: vault,
                importer: ccSwitchImporter
            )
            reload()
            let skipped = summary.skippedNames.isEmpty
                ? ""
                : "；跳过缺少必要字段的：\(summary.skippedNames.joined(separator: "、"))"
            statusMessage = "已从 CC Switch 导入 \(summary.importedCount) 个配置\(skipped)。未改动 CC Switch 和当前运行配置"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reload() {
        profiles = store.profiles
    }
}
