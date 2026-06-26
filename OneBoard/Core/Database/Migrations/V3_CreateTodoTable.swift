import GRDB

/// V3 迁移：创建待办事项表 + FTS5 全文搜索
enum V3_CreateTodoTable {
    static let identifier = "v3_create_todos"

    static func migrate(_ db: Database) throws {
        try db.create(table: "todos") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("text", .text).notNull()
            t.column("isCompleted", .boolean).notNull().defaults(to: false)
            t.column("priority", .text).notNull().defaults(to: "medium")  // "high" | "medium" | "low"
            t.column("sourceAppBundleId", .text)     // 来源应用 Bundle ID
            t.column("dueDate", .datetime)           // 截止日期（可空）
            t.column("completedAt", .datetime)       // 完成时间（可空）
            t.column("createdAt", .datetime).notNull()
        }

        // 索引
        try db.create(index: "idx_todos_completed", on: "todos", columns: ["isCompleted"])
        try db.create(index: "idx_todos_created_at", on: "todos", columns: ["createdAt"])
        try db.create(index: "idx_todos_due_date", on: "todos", columns: ["dueDate"])
        try db.create(index: "idx_todos_priority", on: "todos", columns: ["priority"])

        // FTS5 全文搜索
        try db.create(virtualTable: "todos_fts", using: FTS5()) { t in
            t.column("text")
            t.content = "todos"
        }
    }
}
