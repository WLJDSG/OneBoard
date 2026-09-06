import Foundation
import CryptoKit

/// 用户选择的 iCloud Drive 目录。只写密文，密钥留在本机 SQLite。
struct FolderConfigurationStore: CloudConfigurationStoring {
    let folder: URL
    let key: Data

    func load() async throws -> ConfigurationSnapshot? {
        try await Task.detached {
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            let url = folder.appendingPathComponent("OneBoard.configuration.encrypted")
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".OneBoard.configuration.encrypted.icloud").path) {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                throw FolderSyncError.downloading
            }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            if (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true {
                return try Self.decrypt(Data(contentsOf: url), key: key)
            }
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
            if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                throw FolderSyncError.downloading
            }
            var result: Result<ConfigurationSnapshot, Error>?
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
                result = Result { try Self.decrypt(Data(contentsOf: coordinated), key: key) }
            }
            if let error { throw error }
            return try result?.get()
        }.value
    }

    func save(_ snapshot: ConfigurationSnapshot) async throws {
        try await Task.detached {
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            let data = try Self.encrypt(snapshot, key: key)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true {
                try data.write(to: folder.appendingPathComponent("OneBoard.configuration.encrypted"), options: .atomic)
                return
            }
            var writeError: Error?
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: folder, options: .forMerging, error: &error) { coordinatedFolder in
                let url = coordinatedFolder.appendingPathComponent("OneBoard.configuration.encrypted")
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let error { throw error }
            if let writeError { throw writeError }
        }.value
    }

    static func encrypt(_ snapshot: ConfigurationSnapshot, key: Data) throws -> Data {
        guard key.count == 32 else { throw FolderSyncError.invalidKey }
        return try AES.GCM.seal(JSONEncoder().encode(snapshot), using: SymmetricKey(data: key)).combined!
    }

    static func decrypt(_ data: Data, key: Data) throws -> ConfigurationSnapshot {
        guard key.count == 32 else { throw FolderSyncError.invalidKey }
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: key))
            return try JSONDecoder().decode(ConfigurationSnapshot.self, from: plain)
        } catch { throw FolderSyncError.invalidKey }
    }
}

enum FolderSyncError: LocalizedError {
    case invalidKey, downloading, setup
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "同步密钥不匹配，或同步文件已损坏；未覆盖云端文件。"
        case .downloading: return "iCloud 正在下载配置，稍后会自动重试。"
        case .setup: return "请先选择 iCloud Drive 中的文件夹，并配置同步密钥。"
        }
    }
}
