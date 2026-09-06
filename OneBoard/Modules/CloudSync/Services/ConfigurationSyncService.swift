import Foundation

struct ConfigurationSyncService {
    private let cloud: CloudConfigurationStoring
    private let repository: PrivateDataRepository
    private let defaults: UserDefaults
    private let sharedDefaults: UserDefaults

    init(
        cloud: CloudConfigurationStoring = CloudKitConfigurationStore(),
        repository: PrivateDataRepository = .shared,
        defaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) ?? .standard
    ) {
        self.cloud = cloud
        self.repository = repository
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
    }

    func synchronize(preferRemote: Bool = false) async throws -> Date {
        let local = try makeLocalSnapshot()
        guard let remote = try await cloud.load() else {
            try await cloud.save(local)
            return local.modifiedAt
        }
        if remote == local { return remote.modifiedAt }
        if preferRemote || remote.modifiedAt > local.modifiedAt {
            try apply(remote)
            return remote.modifiedAt
        }
        try await cloud.save(local)
        return local.modifiedAt
    }

    func backup(restore: Bool = false) async throws -> Date {
        if restore, let remote = try await cloud.load() {
            try apply(remote)
            return Date()
        }
        // 先检查备份是否完整/已下载，不能覆盖未下载或无法解析的现有备份。
        _ = try await cloud.load()
        try await cloud.save(makeLocalSnapshot())
        return Date()
    }

    func makeLocalSnapshot() throws -> ConfigurationSnapshot {
        let records = try repository.exportConfiguration()
        let change = defaults.object(forKey: Constants.UserDefaultsKeys.iCloudLastLocalChange) as? Date ?? .distantPast
        let databaseChange = (records.privateRecords.map(\.updatedAt) + records.applicationState.map(\.updatedAt)).max() ?? .distantPast
        return ConfigurationSnapshot(
            schema: ConfigurationSnapshot.schemaVersion,
            modifiedAt: max(change, databaseChange),
            standardDefaults: try ConfigurationSnapshotCodec.encodeDefaults(defaults, keys: ConfigurationSnapshotCodec.standardKeys),
            sharedDefaults: try ConfigurationSnapshotCodec.encodeDefaults(sharedDefaults, keys: ConfigurationSnapshotCodec.sharedKeys),
            privateRecords: records.privateRecords,
            applicationState: records.applicationState
        )
    }

    func apply(_ snapshot: ConfigurationSnapshot) throws {
        guard snapshot.schema == ConfigurationSnapshot.schemaVersion else { throw ConfigurationSyncError.invalidSnapshot }
        try ConfigurationSnapshotCodec.applyDefaults(snapshot.standardDefaults, to: defaults, keys: ConfigurationSnapshotCodec.standardKeys)
        try ConfigurationSnapshotCodec.applyDefaults(snapshot.sharedDefaults, to: sharedDefaults, keys: ConfigurationSnapshotCodec.sharedKeys)
        try repository.importConfiguration(privateRecords: snapshot.privateRecords, applicationState: snapshot.applicationState)
        defaults.set(snapshot.modifiedAt, forKey: Constants.UserDefaultsKeys.iCloudLastLocalChange)
        NotificationCenter.default.post(name: .oneBoardConfigurationDidSync, object: nil)
    }
}
