import GRDB

/// V4 迁移：为待办事项表添加 sortOrder 列，支持拖拽排序
enum V4_AddTodoSortOrder {
    static let identifier = "v4_add_todo_sort_order"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "todos") { t in
            t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
        }
        try db.create(index: "idx_todos_sort_order", on: "todos", columns: ["sortOrder"])
    }
}
