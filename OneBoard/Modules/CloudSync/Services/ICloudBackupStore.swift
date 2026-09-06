import Foundation

/// 重装恢复用途：本机配置是日常备份源，首次启用或显式恢复才读取云端。
struct ICloudBackupStore: CloudConfigurationStoring {
    static var driveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static var directory: URL { driveRoot.appendingPathComponent("app/oneboard", isDirectory: true) }
    let directory: URL
    init(directory: URL = Self.directory) { self.directory = directory }
    var file: URL { directory.appendingPathComponent("configuration.json") }

    func load() async throws -> ConfigurationSnapshot? {
        try await Task.detached {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".configuration.json.icloud").path) {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
                throw FolderSyncError.downloading
            }
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
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
            var error: NSError?
            var result: Result<Void, Error>?
            NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &error) { url in
                result = Result {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let previous = try Data(contentsOf: url)
                        if previous == payload { return }
                        try previous.write(to: directory.appendingPathComponent("configuration.previous.json"), options: .atomic)
                    }
                    try payload.write(to: url, options: .atomic)
                }
            }
            if let error { throw error }
            try result?.get()
        }.value
    }
}
