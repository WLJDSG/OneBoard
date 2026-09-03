import GRDB

enum V5_CreatePrivateDataTables {
    static let identifier = "v5_create_private_data_tables"

    static func migrate(_ db: Database) throws {
        try db.create(table: "private_records") { table in
            table.column("namespace", .text).notNull()
            table.column("record_id", .text).notNull()
            table.column("payload", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
            table.primaryKey(["namespace", "record_id"])
        }
        try db.create(table: "application_state") { table in
            table.column("key", .text).primaryKey()
            table.column("value", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }
}
