import Foundation
import GRDB

/// 待办事项数据库操作
final class TodoRepository {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    // MARK: - 插入

    /// 插入一条待办事项，返回新 ID
    func insert(_ item: TodoItem) async throws -> Int64 {
        let queue = try dbManager.queue
        return try await queue.write { db in
            var item = item
            try item.insert(db)
            let id = db.lastInsertedRowID

            // 同步 FTS 索引
            try db.execute(
                sql: "INSERT INTO todos_fts(rowid, text) VALUES (?, ?)",
                arguments: [id, item.text]
            )

            return id
        }
    }

    // MARK: - 查询

    /// 获取所有未完成的待办（优先级排序 + 过期优先 + 时间倒序）
    func fetchActive(limit: Int = 200) async throws -> [TodoItem] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try TodoItem
                .filter(TodoItem.Columns.isCompleted == false)
                .order(
                    TodoItem.Columns.priority == "high",
                    TodoItem.Columns.dueDate.ascNullsLast,
                    TodoItem.Columns.createdAt.desc
                )
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// 获取最近完成的事项
    func fetchRecentlyCompleted(limit: Int = 50) async throws -> [TodoItem] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try TodoItem
                .filter(TodoItem.Columns.isCompleted == true)
                .filter(TodoItem.Columns.completedAt != nil)
                .order(TodoItem.Columns.completedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// 搜索（FTS5 + 非完成优先）
    func search(query: String, limit: Int = 50) async throws -> [TodoItem] {
        let queue = try dbManager.queue
        let terms = query
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        return try await queue.read { db in
            let ftsQuery = terms.map { "\"\($0)\"" }.joined(separator: " AND ")
            let sql = """
                SELECT todos.* FROM todos
                JOIN todos_fts ON todos_fts.rowid = todos.id
                WHERE todos_fts MATCH ?
                ORDER BY todos.isCompleted ASC, todos.createdAt DESC
                LIMIT ?
                """
            return try TodoItem.fetchAll(db, sql: sql, arguments: [ftsQuery, limit])
        }
    }

    // MARK: - 更新

    /// 标记完成
    func markCompleted(id: Int64) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE todos SET isCompleted = 1, completedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    /// 取消完成（恢复为未完成）
    func markUncompleted(id: Int64) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE todos SET isCompleted = 0, completedAt = NULL WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// 更新优先级
    func updatePriority(id: Int64, priority: Priority) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE todos SET priority = ? WHERE id = ?",
                arguments: [priority.rawValue, id]
            )
        }
    }

    /// 更新截止日期
    func updateDueDate(id: Int64, dueDate: Date?) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE todos SET dueDate = ? WHERE id = ?",
                arguments: [dueDate, id]
            )
        }
    }

    // MARK: - 删除

    /// 删除单条
    func delete(id: Int64) async throws {
        let queue = try dbManager.queue
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM todos_fts WHERE rowid = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM todos WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - 统计

    /// 每日完成数量（过去 N 天）
    func dailyCompletionCount(days: Int = 30) async throws -> [(date: String, count: Int)] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            let sql = """
                SELECT date(completedAt) as day, count(*) as cnt
                FROM todos
                WHERE isCompleted = 1 AND completedAt >= date('now', '-\(days) days')
                GROUP BY day
                ORDER BY day ASC
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.compactMap { row in
                guard let day: String = row["day"],
                      let cnt: Int = row["cnt"] else { return nil }
                return (day, cnt)
            }
        }
    }

    /// 来源应用统计
    func sourceAppStats() async throws -> [(bundleId: String?, count: Int)] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            let sql = """
                SELECT sourceAppBundleId, count(*) as cnt
                FROM todos
                WHERE isCompleted = 1
                GROUP BY sourceAppBundleId
                ORDER BY cnt DESC
                """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.compactMap { row in
                let cnt: Int = row["cnt"] ?? 0
                let bid: String? = row["sourceAppBundleId"]
                return (bid, cnt)
            }
        }
    }

    /// 总完成数
    func totalCompleted() async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try TodoItem.filter(TodoItem.Columns.isCompleted == true).fetchCount(db)
        }
    }

    /// 总待办数
    func totalCount() async throws -> Int {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try TodoItem.fetchCount(db)
        }
    }

    /// 获取过期的未完成项
    func fetchOverdue() async throws -> [TodoItem] {
        let queue = try dbManager.queue
        return try await queue.read { db in
            try TodoItem
                .filter(TodoItem.Columns.isCompleted == false)
                .filter(TodoItem.Columns.dueDate != nil)
                .filter(TodoItem.Columns.dueDate < Date())
                .fetchAll(db)
        }
    }

    // MARK: - 保留策略

    /// 删除超过保留天数的已完成记录（-1 表示永久保留）
    func deleteCompletedOlderThan(days: Int) async throws -> Int {
        guard days > 0 else { return 0 }  // 永久保留
        let queue = try dbManager.queue
        return try await queue.write { db in
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            try db.execute(
                sql: """
                    DELETE FROM todos WHERE isCompleted = 1 AND completedAt < ?
                    """,
                arguments: [cutoffDate]
            )
            return db.changesCount
        }
    }

    /// 应用保留策略
    func applyRetentionPolicy() async {
        let days = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.todoRetentionDays)
        // 默认永久保留（days == -1 或未设置）
        let retentionDays = days == 0 ? -1 : days

        do {
            let deleted = try await deleteCompletedOlderThan(days: retentionDays)
            if deleted > 0 {
                print("[TodoRepository] 保留策略清理: 删除 \(deleted) 条已完成的待办")
            }
        } catch {
            print("[TodoRepository] 保留策略执行失败: \(error)")
        }
    }
}
