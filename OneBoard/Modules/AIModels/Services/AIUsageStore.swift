import Foundation
import GRDB

struct AIUsageEvent: Codable {
    var id: String
    var credentialID: String
    var timestamp: Double
    var input: Int64
    var output: Int64
    var cacheRead: Int64
    var cacheCreation: Int64
}

struct AITokenTotals: Equatable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheCreation: Int64 = 0
    var total: Int64 { input + output + cacheRead + cacheCreation }
}

/// 输入列为非缓存输入；总量包含缓存命中，避免 OpenAI input 重复累计。
final class AIUsageStore: @unchecked Sendable {
    static let shared = AIUsageStore()
    private let queueOverride: DatabaseQueue?
    init(queue: DatabaseQueue? = nil) { queueOverride = queue }
    private var queue: DatabaseQueue { get throws { try queueOverride ?? DatabaseManager.shared.queue } }

    func record(_ event: AIUsageEvent) throws {
        guard [event.input, event.output, event.cacheRead, event.cacheCreation].allSatisfy({ $0 >= 0 }) else { return }
        try queue.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO ai_usage_events
                (id, credential_id, timestamp, input_tokens, output_tokens, cache_read, cache_creation)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [event.id, event.credentialID, event.timestamp, event.input, event.output, event.cacheRead, event.cacheCreation])
        }
    }

    func today(credentialID: String, now: Date = Date(), calendar: Calendar = .current) throws -> Int64 {
        try totals(credentialID: credentialID, day: now, calendar: calendar).total
    }

    func totals(credentialID: String, day: Date? = nil, calendar: Calendar = .current) throws -> AITokenTotals {
        var condition = "credential_id = ?"
        var arguments: StatementArguments = [credentialID]
        if let day {
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            condition += " AND timestamp >= ? AND timestamp < ?"
            arguments += [start.timeIntervalSince1970, end.timeIntervalSince1970]
        }
        return try queue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COALESCE(SUM(input_tokens), 0) AS input, COALESCE(SUM(output_tokens), 0) AS output,
                    COALESCE(SUM(cache_read), 0) AS cache_read, COALESCE(SUM(cache_creation), 0) AS cache_creation
                FROM ai_usage_events WHERE \(condition)
                """, arguments: arguments)!
            return AITokenTotals(input: row["input"], output: row["output"], cacheRead: row["cache_read"], cacheCreation: row["cache_creation"])
        }
    }

    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE ai_usage_events (
                id TEXT PRIMARY KEY, credential_id TEXT NOT NULL, timestamp DOUBLE NOT NULL,
                input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
                cache_read INTEGER NOT NULL, cache_creation INTEGER NOT NULL
            );
            CREATE INDEX ai_usage_events_credential_time ON ai_usage_events(credential_id, timestamp);
            """)
    }
}
