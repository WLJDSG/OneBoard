import Foundation
import GRDB

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
    }

    private func resolvedQueue() throws -> DatabaseQueue {
        if let queueOverride { return queueOverride }
        return try DatabaseManager.shared.queue
    }
}
