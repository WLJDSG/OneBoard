import Foundation

/// Codex 当前运行凭据只物化到 `auth.json`；OneBoard 的持久化副本位于 SQLite。
/// 每次访问前强制把 Codex 配置切换为 file，避免 Codex 或 OneBoard 访问系统钥匙串。
final class CodexAuthCredentialStore: CodexAuthCacheFileHandling {
    private let authFile: CodexAuthCacheFile
    private let configURL: URL
    private let fileManager: FileManager

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        let resolvedHome = codexHome.resolvingSymlinksInPath().standardizedFileURL
        authFile = CodexAuthCacheFile(
            url: resolvedHome.appendingPathComponent("auth.json"),
            fileManager: fileManager
        )
        configURL = resolvedHome.appendingPathComponent("config.toml")
        self.fileManager = fileManager
    }

    var exists: Bool { authFile.exists }

    func read() throws -> Data {
        try enforceFileStorage()
        let data = try authFile.read()
        try validate(data)
        return data
    }

    func replace(with data: Data) throws {
        try validate(data)
        try enforceFileStorage()
        try authFile.replace(with: data)
    }

    static func rewriteConfigForFileStorage(_ existing: String) -> String {
        var lines: [String] = []
        var reachedFirstTable = false
        for line in existing.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { reachedFirstTable = true }
            if !reachedFirstTable,
               let separator = trimmed.firstIndex(of: "="),
               trimmed[..<separator].trimmingCharacters(in: .whitespaces) == "cli_auth_credentials_store" {
                continue
            }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return "cli_auth_credentials_store = \"file\"\n"
            + (lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n") + "\n")
    }

    private func enforceFileStorage() throws {
        let existing: String
        if fileManager.fileExists(atPath: configURL.path) {
            if try configURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CodexAccountError.unsafeAuthCachePath
            }
            existing = try String(contentsOf: configURL, encoding: .utf8)
        } else {
            existing = ""
        }
        let updated = Self.rewriteConfigForFileStorage(existing)
        guard updated != existing else { return }

        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let backup = configURL.appendingPathExtension("oneboard-auth-store-backup")
        if !fileManager.fileExists(atPath: backup.path) {
            try Data(existing.utf8).write(to: backup, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try Data(updated.utf8).write(to: configURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func validate(_ data: Data) throws {
        guard !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw CodexAccountError.invalidAuthCache
        }
    }
}
