import Foundation
import AppKit

@MainActor
final class CloudSyncViewModel: ObservableObject {
    static let shared = CloudSyncViewModel()

    @Published private(set) var isSyncing = false
    @Published private(set) var statusMessage = "尚未同步"
    @Published private(set) var lastSync: Date?
    private var pollingTask: Task<Void, Never>?

    private let service: ConfigurationSyncService?
    private var observers: [NSObjectProtocol] = []
    private var scheduledTask: Task<Void, Never>?
    private var isApplyingRemote = false
    private var defaultsFingerprint = Data()
    private var needsRestore = false

    init(service: ConfigurationSyncService? = nil) {
        self.service = service
        lastSync = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.iCloudLastSync) as? Date
        defaultsFingerprint = Self.makeDefaultsFingerprint()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.preferencesDidChange() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .oneBoardPrivateConfigurationDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSynchronization() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.iCloudSyncEnabled)
    }

    var isAvailable: Bool {
        true
    }

    private func configuredService() throws -> ConfigurationSyncService {
        if let service { return service }
        guard FileManager.default.fileExists(atPath: ICloudBackupStore.driveRoot.path) else {
            throw ConfigurationSyncError.iCloudUnavailable
        }
        return ConfigurationSyncService(cloud: ICloudBackupStore())
    }

    func restoreBackup() {
        guard !isSyncing else { return }
        needsRestore = true
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.iCloudSyncEnabled)
        startPolling()
        Task { await synchronize(preferRemote: true) }
    }

    func revealBackup() {
        NSWorkspace.shared.open(ICloudBackupStore.directory)
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.synchronize()
            }
        }
    }

    func startIfEnabled() {
        // 新安装首次启动发现既有备份时恢复；显式关闭过同步的用户不自动开启。
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.iCloudSyncEnabled) == nil,
           FileManager.default.fileExists(atPath: ICloudBackupStore.directory.path) {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.iCloudSyncEnabled)
            Task { await synchronize(preferRemote: true) }
        }
        guard isEnabled else { return }
        startPolling()
        Task { await synchronize(preferRemote: lastSync == nil) }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Constants.UserDefaultsKeys.iCloudSyncEnabled)
        statusMessage = enabled ? "正在连接 iCloud…" : "同步已关闭，本地配置会保留"
        guard enabled else { scheduledTask?.cancel(); pollingTask?.cancel(); pollingTask = nil; return }
        startPolling()
        Task { await synchronize(preferRemote: lastSync == nil) }
    }

    func syncNow() {
        guard isEnabled else { return }
        Task { await synchronize() }
    }

    private func preferencesDidChange() {
        guard isEnabled, !isApplyingRemote else { return }
        let fingerprint = Self.makeDefaultsFingerprint()
        guard fingerprint != defaultsFingerprint else { return }
        defaultsFingerprint = fingerprint
        let now = Date()
        if let previous = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.iCloudLastLocalChange) as? Date,
           now.timeIntervalSince(previous) < 0.25 { return }
        UserDefaults.standard.set(now, forKey: Constants.UserDefaultsKeys.iCloudLastLocalChange)
        scheduleSynchronization()
    }

    private func scheduleSynchronization() {
        guard isEnabled, !isApplyingRemote else { return }
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    private func synchronize(preferRemote: Bool = false) async {
        guard isEnabled, !isSyncing else { return }
        needsRestore = needsRestore || preferRemote
        isSyncing = true
        statusMessage = "正在同步全部配置…"
        isApplyingRemote = true
        defer { isApplyingRemote = false; isSyncing = false }
        do {
            let service = try configuredService()
            let restoring = needsRestore
            let date = try await service.backup(restore: restoring)
            needsRestore = false
            defaultsFingerprint = Self.makeDefaultsFingerprint()
            lastSync = date
            UserDefaults.standard.set(date, forKey: Constants.UserDefaultsKeys.iCloudLastSync)
            statusMessage = restoring ? "已恢复或创建 iCloud 配置备份" : "配置已备份到 iCloud Drive/app/oneboard"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static func makeDefaultsFingerprint() -> Data {
        let standard = (try? ConfigurationSnapshotCodec.encodeDefaults(.standard, keys: ConfigurationSnapshotCodec.standardKeys)) ?? Data()
        let shared = (try? ConfigurationSnapshotCodec.encodeDefaults(UserDefaults(suiteName: Constants.appGroupIdentifier) ?? .standard, keys: ConfigurationSnapshotCodec.sharedKeys)) ?? Data()
        return standard + shared
    }
}
