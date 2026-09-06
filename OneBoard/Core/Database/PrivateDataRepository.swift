import Foundation
import GRDB

struct PrivateConfigurationRecord: Codable, Equatable, Sendable {
    let namespace: String
    let recordID: String
    let payload: Data
    let updatedAt: Date
}

struct ApplicationConfigurationRecord: Codable, Equatable, Sendable {
    let key: String
    let value: Data
    let updatedAt: Date
}

final class PrivateDataRepository: @unchecked Sendable {
    static let shared = PrivateDataRepository()

    private let queueOverride: DatabaseQueue?

    init(queue: DatabaseQueue? = nil) {
        queueOverride = queue
    }

    func save(_ payload: Data, namespace: String, recordID: String) throws {
        let queue = try resolvedQueue()
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO private_records (namespace, record_id, payload, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(namespace, record_id) DO UPDATE SET
                    payload = excluded.payload,
                    updated_at = excluded.updated_at
                """,
                arguments: [namespace, recordID, payload, Date()]
            )
        }
        if namespace != "ai_quota" { NotificationCenter.default.post(name: .oneBoardPrivateConfigurationDidChange, object: nil) }
    }

    func load(namespace: String, recordID: String) throws -> Data? {
        let queue = try resolvedQueue()
        return try queue.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT payload FROM private_records WHERE namespace = ? AND record_id = ?",
                arguments: [namespace, recordID]
            )
        }
    }

    func contains(namespace: String, recordID: String) -> Bool {
        (try? load(namespace: namespace, recordID: recordID)) != nil
    }

    func delete(namespace: String, recordID: String) throws {
        let queue = try resolvedQueue()
        _ = try queue.write { db in
            try db.execute(
                sql: "DELETE FROM private_records WHERE namespace = ? AND record_id = ?",
                arguments: [namespace, recordID]
            )
        }
        if namespace != "ai_quota" { NotificationCenter.default.post(name: .oneBoardPrivateConfigurationDidChange, object: nil) }
    }

    func saveState(_ value: Data, key: String) throws {
        let queue = try resolvedQueue()
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO application_state (key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = excluded.updated_at
                """,
                arguments: [key, value, Date()]
            )
        }
        NotificationCenter.default.post(name: .oneBoardPrivateConfigurationDidChange, object: nil)
    }

    func loadState(key: String) throws -> Data? {
        let queue = try resolvedQueue()
        return try queue.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value FROM application_state WHERE key = ?",
                arguments: [key]
            )
        }
    }

    func deleteState(key: String) throws {
        let queue = try resolvedQueue()
        _ = try queue.write { db in
            try db.execute(sql: "DELETE FROM application_state WHERE key = ?", arguments: [key])
        }
        NotificationCenter.default.post(name: .oneBoardPrivateConfigurationDidChange, object: nil)
    }

    func exportConfiguration(excludingNamespaces: Set<String> = ["ai_quota", "local_sync"]) throws -> (privateRecords: [PrivateConfigurationRecord], applicationState: [ApplicationConfigurationRecord]) {
        let queue = try resolvedQueue()
        return try queue.read { db in
            let privateRecords = try Row.fetchAll(db, sql: "SELECT namespace, record_id, payload, updated_at FROM private_records ORDER BY namespace, record_id").compactMap { row -> PrivateConfigurationRecord? in
                let namespace: String = row["namespace"]
                guard !excludingNamespaces.contains(namespace) else { return nil }
                return PrivateConfigurationRecord(namespace: namespace, recordID: row["record_id"], payload: row["payload"], updatedAt: row["updated_at"])
            }
            let applicationState = try Row.fetchAll(db, sql: "SELECT key, value, updated_at FROM application_state ORDER BY key").map { row in
                ApplicationConfigurationRecord(key: row["key"], value: row["value"], updatedAt: row["updated_at"])
            }
            return (privateRecords, applicationState)
        }
    }

    func importConfiguration(privateRecords: [PrivateConfigurationRecord], applicationState: [ApplicationConfigurationRecord]) throws {
        let queue = try resolvedQueue()
        try queue.write { db in
            // 云端快照是配置真值；保留本机额度缓存，但让远端删除也能传播。
            try db.execute(sql: "DELETE FROM private_records WHERE namespace NOT IN ('ai_quota', 'local_sync')")
            try db.execute(sql: "DELETE FROM application_state")
            for record in privateRecords {
                guard record.namespace != "local_sync", record.namespace != "ai_quota" else { continue }
                try db.execute(sql: """
                    INSERT INTO private_records (namespace, record_id, payload, updated_at) VALUES (?, ?, ?, ?)
                    ON CONFLICT(namespace, record_id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
                    """, arguments: [record.namespace, record.recordID, record.payload, record.updatedAt])
            }
            for record in applicationState {
                try db.execute(sql: """
                    INSERT INTO application_state (key, value, updated_at) VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                    """, arguments: [record.key, record.value, record.updatedAt])
            }
        }
        NotificationCenter.default.post(name: .oneBoardPrivateConfigurationDidChange, object: nil)
    }

    private func resolvedQueue() throws -> DatabaseQueue {
        if let queueOverride { return queueOverride }
        return try DatabaseManager.shared.queue
    }
}
