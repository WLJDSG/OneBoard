import Foundation
import GRDB

/// 文件暂存数据库操作
final class FileStagingRepository {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    // MARK: - CRUD

    func insert(_ file: StagedFile) async throws -> Int64 {
        let queue = try dbManager.queue
        return try await queue.write { db in
            var file = file
            try file.insert(db)
            return db.lastInsertedRowID
        }
    }

    func fetchAll() async throws -> [StagedFile] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try StagedFile
                .order(StagedFile.Columns.stagedAt.desc)
                .fetchAll(db)
        }
    }

    func delete(id: Int64) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM staged_files WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func deleteAll() async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.write { db in
            try db.execute(sql: "DELETE FROM staged_files")
            return db.changesCount
        }
    }

    func count() async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try StagedFile.fetchCount(db)
        }
    }
}