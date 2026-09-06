import Foundation

/// 重装恢复用途：本机配置是日常备份源，首次启用或显式恢复才读取云端。
struct ICloudBackupStore: CloudConfigurationStoring {
    static var driveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static var directory: URL { driveRoot.appendingPathComponent("app/oneboard", isDirectory: true) }
    let directory: URL
    private let authorization: AuthorizedFolder?
    init(directory: URL = Self.directory, authorization: AuthorizedFolder? = nil) {
        self.directory = directory; self.authorization = authorization
    }
    var file: URL { directory.appendingPathComponent("configuration.json") }

    func load() async throws -> ConfigurationSnapshot? {
        try await Task.detached {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".configuration.json.icloud").path) {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
                throw FolderSyncError.downloading
            }
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            if (try? directory.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true {
                let snapshot = try JSONDecoder().decode(ConfigurationSnapshot.self, from: Data(contentsOf: file))
                guard snapshot.schema == ConfigurationSnapshot.schemaVersion else { throw ConfigurationSyncError.invalidSnapshot }
                return snapshot
            }
            var error: NSError?
            var result: Result<ConfigurationSnapshot, Error>?
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { url in
                result = Result { try JSONDecoder().decode(ConfigurationSnapshot.self, from: Data(contentsOf: url)) }
            }
            if let error { throw error }
            guard let snapshot = try result?.get(), snapshot.schema == ConfigurationSnapshot.schemaVersion else {
                throw ConfigurationSyncError.invalidSnapshot
            }
            return snapshot
        }.value
    }

    func save(_ snapshot: ConfigurationSnapshot) async throws {
        try await Task.detached {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = try encoder.encode(snapshot)
            if (try? directory.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true {
                try Self.write(payload, to: directory)
                return
            }
            var error: NSError?
            var result: Result<Void, Error>?
            NSFileCoordinator().coordinate(writingItemAt: directory, options: .forMerging, error: &error) { coordinatedDirectory in
                result = Result {
                    let url = coordinatedDirectory.appendingPathComponent("configuration.json")
                    if FileManager.default.fileExists(atPath: url.path) {
                        let previous = try Data(contentsOf: url)
                        if previous == payload { return }
                        try previous.write(to: coordinatedDirectory.appendingPathComponent("configuration.previous.json"), options: .atomic)
                    }
                    try payload.write(to: url, options: .atomic)
                }
            }
            if let error { throw error }
            try result?.get()
        }.value
    }

    private static func write(_ payload: Data, to directory: URL) throws {
        let url = directory.appendingPathComponent("configuration.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            if previous == payload { return }
            try previous.write(to: directory.appendingPathComponent("configuration.previous.json"), options: .atomic)
        }
        try payload.write(to: url, options: .atomic)
    }
}
