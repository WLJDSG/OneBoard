import GRDB

/// V2 迁移：创建文件暂存表
enum V2_CreateFileStageTable {
    static let identifier = "v2_create_staged_files"

    static func migrate(_ db: Database) throws {
        try db.create(table: "staged_files") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("fileName", .text).notNull()
            t.column("fileURL", .text).notNull()
            t.column("fileSize", .integer).notNull()
            t.column("bookmarkData", .blob)
            t.column("thumbnailData", .blob)
            t.column("stagedAt", .datetime).notNull()
        }

        try db.create(
            index: "idx_staged_files_staged_at",
            on: "staged_files",
            columns: ["stagedAt"]
        )
    }
}