import Foundation
import GRDB

/// 剪贴板数据库操作
final class ClipboardRepository {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    // MARK: - 插入

    /// 插入一条剪贴板记录
    func insert(_ entry: ClipboardEntry) async throws -> Int64 {
        let queue = try dbManager.queue
        return try await queue.write { db in
            var entry = entry
            try entry.insert(db)
            let id = db.lastInsertedRowID

            // 同步更新 FTS 索引
            if let plainText = entry.plainText, !plainText.isEmpty {
                try db.execute(
                    sql: "INSERT INTO clipboard_fts(rowid, plainText) VALUES (?, ?)",
                    arguments: [id, plainText]
                )
            }

            return id
        }
    }

    // MARK: - 查询

    /// 获取所有记录（置顶优先 + 时间倒序）
    func fetchAll(limit: Int = 200) async throws -> [ClipboardEntry] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try ClipboardEntry
                .order(
                    ClipboardEntry.Columns.isPinned.desc,
                    ClipboardEntry.Columns.createdAt.desc
                )
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// 搜索（FTS5）
    func search(query: String, limit: Int = 50) async throws -> [ClipboardEntry] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            let searchPattern = query
                .split(separator: " ")
                .map { "\"\($0)\"" }
                .joined(separator: " AND ")

            let sql = """
                SELECT clipboard_history.*
                FROM clipboard_history
                JOIN clipboard_fts ON clipboard_history.id = clipboard_fts.rowid
                WHERE clipboard_fts MATCH ?
                ORDER BY clipboard_history.isPinned DESC, clipboard_history.createdAt DESC
                LIMIT ?
                """
            return try ClipboardEntry.fetchAll(db, sql: sql, arguments: [searchPattern, limit])
        }
    }

    // MARK: - 更新

    /// 切换置顶状态
    func togglePin(id: Int64) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_history SET isPinned = NOT isPinned WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - 删除

    /// 删除单条记录
    func delete(id: Int64) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            // 先删除 FTS 索引
            try db.execute(sql: "DELETE FROM clipboard_fts WHERE rowid = ?", arguments: [id])
            // 再删除主表记录
            try db.execute(sql: "DELETE FROM clipboard_history WHERE id = ?", arguments: [id])
        }
    }

    /// 删除超过保留天数的记录
    func deleteOlderThan(days: Int) async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.write { db in
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            try db.execute(
                sql: """
                    DELETE FROM clipboard_history
                    WHERE isPinned = 0 AND createdAt < ?
                    """,
                arguments: [cutoffDate]
            )
            return db.changesCount
        }
    }

    /// 删除超出数量限制的记录（保留最新的 N 条 + 所有置顶记录）
    func deleteExcess(keepingCount: Int) async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.write { db in
            // 获取需要保留的最小 ID
            let thresholdSQL = """
                SELECT id FROM clipboard_history
                WHERE isPinned = 0
                ORDER BY createdAt DESC
                LIMIT 1 OFFSET ?
                """
            guard let thresholdRow = try Row.fetchOne(db, sql: thresholdSQL, arguments: [keepingCount]),
                  let thresholdId: Int64 = thresholdRow["id"] else {
                return 0
            }

            try db.execute(
                sql: """
                    DELETE FROM clipboard_history
                    WHERE isPinned = 0 AND id < ?
                    """,
                arguments: [thresholdId]
            )
            return db.changesCount
        }
    }

    /// 清空所有非置顶记录
    func clearAll() async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM clipboard_history WHERE isPinned = 0"
            )
            return db.changesCount
        }
    }

    // MARK: - 保留策略

    /// 应用保留策略（按条数 + 按天数）
    func applyRetentionPolicy() async {
        let maxItems = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.maxClipboardItems)
        let retentionDays = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.retentionDays)

        let maxCount = maxItems > 0 ? maxItems : Constants.defaultMaxClipboardItems
        let days = retentionDays > 0 ? retentionDays : Constants.defaultRetentionDays

        do {
            let deletedByDays = try await deleteOlderThan(days: days)
            let deletedByCount = try await deleteExcess(keepingCount: maxCount)
            if deletedByDays > 0 || deletedByCount > 0 {
                print("[ClipboardRepository] 保留策略清理: 按天数删除 \(deletedByDays) 条, 按数量删除 \(deletedByCount) 条")
            }
        } catch {
            print("[ClipboardRepository] 保留策略执行失败: \(error)")
        }
    }
}