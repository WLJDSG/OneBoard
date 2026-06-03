import Foundation
import GRDB

/// 数据库管理器 - 单例
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private init() {}

    /// 获取数据库队列
    var queue: DatabaseQueue {
        get throws {
            if let dbQueue = dbQueue {
                return dbQueue
            }
            throw DatabaseError.notInitialized
        }
    }

    /// 初始化数据库（应用启动时调用）
    func initialize() throws {
        let dbPath = databasePath()
        let queue = try DatabaseQueue(path: dbPath)

        // 注册迁移
        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1_CreateClipboardTable.identifier) { db in
            try V1_CreateClipboardTable.migrate(db)
        }
        migrator.registerMigration(V2_CreateFileStageTable.identifier) { db in
            try V2_CreateFileStageTable.migrate(db)
        }

        try migrator.migrate(queue)
        self.dbQueue = queue
    }

    /// 数据库文件路径
    private func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appFolder = appSupport.appendingPathComponent(Constants.appName)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder.appendingPathComponent(Constants.databaseFileName).path
    }
}

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed(String)
}