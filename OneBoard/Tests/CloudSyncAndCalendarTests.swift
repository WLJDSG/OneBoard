import AppKit
import GRDB
import XCTest
@testable import OneBoardKit

final class CloudSyncAndCalendarTests: XCTestCase {
    func testCalendarGridStartsOnConfiguredMonday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let days = CalendarGrid(calendar: calendar, weekStart: .monday).days(containing: month, today: month)

        XCTAssertEqual(days.count % 7, 0)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(days.first?.date)), 2)
        XCTAssertEqual(days.filter(\.isToday).map(\.day), [15])
    }

    func testCalendarGridCanStartOnSunday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let days = CalendarGrid(calendar: calendar, weekStart: .sunday).days(containing: month)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(days.first?.date)), 1)
    }

    func testConfigurationDefaultsRoundTripOnlyWhitelistedKeys() throws {
        let suite = "OneBoard.CloudSyncTests.\(UUID().uuidString)"
        let source = try XCTUnwrap(UserDefaults(suiteName: suite))
        let target = try XCTUnwrap(UserDefaults(suiteName: suite + ".target"))
        defer { source.removePersistentDomain(forName: suite); target.removePersistentDomain(forName: suite + ".target") }
        source.set(500, forKey: Constants.UserDefaultsKeys.maxClipboardItems)
        source.set("do-not-sync", forKey: Constants.UserDefaultsKeys.selectedSettingsTab)

        let data = try ConfigurationSnapshotCodec.encodeDefaults(source, keys: ConfigurationSnapshotCodec.standardKeys)
        try ConfigurationSnapshotCodec.applyDefaults(data, to: target, keys: ConfigurationSnapshotCodec.standardKeys)

        XCTAssertEqual(target.integer(forKey: Constants.UserDefaultsKeys.maxClipboardItems), 500)
        XCTAssertNil(target.string(forKey: Constants.UserDefaultsKeys.selectedSettingsTab))
    }

    func testLongScreenshotRouteReturnsToCaptureService() {
        XCTAssertEqual(ScreenshotLockedRoute.route(for: .longCapture), .longCapture)
    }

    func testLongScreenshotStitcherAddsOnlyNonOverlappingArea() throws {
        let first = NSImage(size: CGSize(width: 40, height: 100))
        let second = NSImage(size: CGSize(width: 40, height: 100))
        let stitched = try XCTUnwrap(LongScreenshotStitcher.stitch([first, second], overlapRatio: 0.2))
        XCTAssertEqual(stitched.size, CGSize(width: 40, height: 180))
    }

    func testTranslationPresetsProvideExpectedOpenAICompatibleDefaults() {
        XCTAssertEqual(TranslationProviderPreset.deepSeek.baseURL, "https://api.deepseek.com/v1")
        XCTAssertEqual(TranslationProviderPreset.deepSeek.model, "deepseek-chat")
        XCTAssertEqual(TranslationServiceType.deepSeek.displayName, "自定义 API")
    }

    func testApplyingCloudConfigurationPropagatesDeletesButKeepsQuotaCache() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.create(table: "private_records") { table in
                table.column("namespace", .text).notNull(); table.column("record_id", .text).notNull()
                table.column("payload", .blob).notNull(); table.column("updated_at", .datetime).notNull()
                table.primaryKey(["namespace", "record_id"])
            }
            try db.create(table: "application_state") { table in
                table.column("key", .text).primaryKey(); table.column("value", .blob).notNull(); table.column("updated_at", .datetime).notNull()
            }
        }
        let repository = PrivateDataRepository(queue: queue)
        try repository.save(Data("old".utf8), namespace: "application_secret", recordID: "deleted")
        try repository.save(Data("quota".utf8), namespace: "ai_quota", recordID: "cached")
        try repository.saveState(Data("old".utf8), key: "deleted_state")
        let remote = PrivateConfigurationRecord(namespace: "application_secret", recordID: "new", payload: Data("new".utf8), updatedAt: Date())

        try repository.importConfiguration(privateRecords: [remote], applicationState: [])

        XCTAssertNil(try repository.load(namespace: "application_secret", recordID: "deleted"))
        XCTAssertEqual(try repository.load(namespace: "application_secret", recordID: "new"), Data("new".utf8))
        XCTAssertEqual(try repository.load(namespace: "ai_quota", recordID: "cached"), Data("quota".utf8))
        XCTAssertNil(try repository.loadState(key: "deleted_state"))
    }
}
