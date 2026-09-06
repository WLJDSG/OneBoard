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
    private var synchronizationInProgress = false

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
        let access = try FolderAccessStore().resolve(.iCloud)
        return ConfigurationSyncService(cloud: ICloudBackupStore(directory: access.url.appendingPathComponent("app/oneboard", isDirectory: true), authorization: access))
    }

    func restoreBackup() {
        guard !synchronizationInProgress else { return }
        needsRestore = true
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.iCloudSyncEnabled)
        startPolling()
        Task { await synchronize(preferRemote: true) }
    }

    func revealBackup() {
        do {
            let access = try FolderAccessStore().resolve(.iCloud)
            let directory = access.url.appendingPathComponent("app/oneboard", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            withExtendedLifetime(access) {
                if !NSWorkspace.shared.open(directory) {
                    statusMessage = "Finder 无法打开备份文件夹：" + directory.path
                }
            }
        } catch { statusMessage = error.localizedDescription }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.synchronize(showProgress: false)
            }
        }
    }

    func folderAuthorizationDidChange() {
        guard isEnabled else { return }
        startPolling()
        Task { await synchronize(preferRemote: lastSync == nil) }
    }

    func startIfEnabled() {
        // 不再自动扫描尚未授权的 iCloud 目录。重装恢复由用户明确触发。
        guard isEnabled else { return }
        guard service != nil || FolderAccessStore().hasRecord(.iCloud) else {
            statusMessage = FolderAccessError.required("iCloud Drive").localizedDescription
            return
        }
        guard pollingTask == nil else { return }
        startPolling()
        Task { await synchronize(preferRemote: lastSync == nil, showProgress: false) }
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
            await self?.synchronize(showProgress: false)
        }
    }

    func synchronize(preferRemote: Bool = false, showProgress: Bool = true) async {
        guard isEnabled, !synchronizationInProgress else { return }
        needsRestore = needsRestore || preferRemote
        synchronizationInProgress = true
        if showProgress { isSyncing = true }
        if showProgress { statusMessage = "正在备份配置…" }
        isApplyingRemote = true
        defer { isApplyingRemote = false; synchronizationInProgress = false; if showProgress { isSyncing = false } }
        do {
            let service = try configuredService()
            let restoring = needsRestore
            let date = try await service.backup(restore: restoring)
            needsRestore = false
            defaultsFingerprint = Self.makeDefaultsFingerprint()
            if lastSync != date {
                lastSync = date
                UserDefaults.standard.set(date, forKey: Constants.UserDefaultsKeys.iCloudLastSync)
            }
            let message = restoring ? "已恢复或创建 iCloud 配置备份" : "配置已备份到 iCloud Drive/app/oneboard"
            if statusMessage != message { statusMessage = message }
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
