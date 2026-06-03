import GRDB

/// V1 迁移：创建剪贴板历史表 + FTS5 全文搜索
enum V1_CreateClipboardTable {
    static let identifier = "v1_create_clipboard"

    static func migrate(_ db: Database) throws {
        // 主表
        try db.create(table: "clipboard_history") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("contentType", .text).notNull()
            t.column("plainText", .text)
            t.column("data", .blob).notNull()
            t.column("sourceAppBundleId", .text)
            t.column("isPinned", .boolean).notNull().defaults(to: false)
            t.column("createdAt", .datetime).notNull()
        }

        // 索引
        try db.create(
            index: "idx_clipboard_created_at",
            on: "clipboard_history",
            columns: ["createdAt"]
        )
        try db.create(
            index: "idx_clipboard_pinned",
            on: "clipboard_history",
            columns: ["isPinned"]
        )

        // FTS5 全文搜索虚拟表
        try db.create(virtualTable: "clipboard_fts", using: FTS5()) { t in
            t.column("plainText")
            t.content = "clipboard_history"
            // 同步触发器将在业务层手动维护
        }
    }
}