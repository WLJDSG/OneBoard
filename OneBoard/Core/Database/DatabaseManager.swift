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
        migrator.registerMigration(V3_CreateTodoTable.identifier) { db in
            try V3_CreateTodoTable.migrate(db)
        }
        migrator.registerMigration(V4_AddTodoSortOrder.identifier) { db in
            try V4_AddTodoSortOrder.migrate(db)
        }
        migrator.registerMigration(V5_CreatePrivateDataTables.identifier) { db in
            try V5_CreatePrivateDataTables.migrate(db)
        }

        migrator.registerMigration("v6_ai_usage_events") { db in
            try AIUsageStore.migrate(db)
        }
        try migrator.migrate(queue)
        try secureDatabaseFiles(at: dbPath)
        self.dbQueue = queue
    }

    /// 数据库文件路径
    private func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appFolder = appSupport.appendingPathComponent(Constants.appName)
        try? FileManager.default.createDirectory(
            at: appFolder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appFolder.path)

        return appFolder.appendingPathComponent(Constants.databaseFileName).path
    }

    private func secureDatabaseFiles(at databasePath: String) throws {
        let fileManager = FileManager.default
        for path in [databasePath, databasePath + "-wal", databasePath + "-shm"]
        where fileManager.fileExists(atPath: path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
}

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed(String)
}
