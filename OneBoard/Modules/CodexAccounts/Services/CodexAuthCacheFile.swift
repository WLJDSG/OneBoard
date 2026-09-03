import Foundation

protocol CodexAuthCacheFileHandling {
    var exists: Bool { get }
    func read() throws -> Data
    func replace(with data: Data) throws
}

final class CodexAuthCacheFile: CodexAuthCacheFileHandling {
    private let url: URL
    private let fileManager: FileManager

    init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
    }

    var exists: Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func read() throws -> Data {
        guard exists else { throw CodexAccountError.authCacheMissing }
        try validatePath()
        let data = try Data(contentsOf: url)
        try validate(data)
        return data
    }

    func replace(with data: Data) throws {
        try validate(data)
        try validatePath()

        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func removeIfPresent() throws {
        guard exists else { return }
        try validatePath()
        try fileManager.removeItem(at: url)
    }

    private func validate(_ data: Data) throws {
        guard !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw CodexAccountError.invalidAuthCache
        }
    }

    private func validatePath() throws {
        guard exists else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw CodexAccountError.unsafeAuthCachePath
        }
    }
}
