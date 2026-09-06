import XCTest
@testable import OneBoardKit

final class CalendarAndBackupRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testEveryMonthKeepsSixRows() throws {
        for year in 2024...2028 {
            for month in 1...12 {
                let date = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: 1)))
                for start in CalendarWeekStart.allCases {
                    let days = CalendarGrid(calendar: calendar, weekStart: start).days(containing: date)
                    XCTAssertEqual(days.count, 42)
                    XCTAssertEqual(Set(days.map(\.date)).count, 42)
                    XCTAssertEqual(days.filter(\.isInDisplayedMonth).count, calendar.range(of: .day, in: .month, for: date)?.count)
                }
            }
        }
    }

    func testChina2026HolidaysAndAllSolarTerms() throws {
        func info(_ month: Int, _ day: Int) throws -> ChineseCalendarInfo {
            ChineseCalendarInfo(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day))), calendar: calendar)
        }
        XCTAssertEqual(try info(9, 20).work, true)
        XCTAssertEqual(try info(9, 25).work, false)
        XCTAssertEqual(try info(9, 25).festival, "中秋节")
        XCTAssertEqual(try info(10, 10).work, true)
        XCTAssertEqual(try info(9, 7).term, "白露")
        XCTAssertEqual(try info(9, 23).term, "秋分")
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let terms = (0..<365).compactMap { offset -> String? in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return ChineseCalendarInfo(date: date, calendar: calendar).term
        }
        XCTAssertEqual(terms.count, 24)
        XCTAssertEqual(Set(terms).count, 24)
    }

    func testPlainBackupRoundTripRetainsPreviousVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ICloudBackupStore(directory: directory)
        let first = ConfigurationSnapshot(schema: 1, modifiedAt: Date(timeIntervalSince1970: 1), standardDefaults: Data(), sharedDefaults: Data(), privateRecords: [], applicationState: [])
        let second = ConfigurationSnapshot(schema: 1, modifiedAt: Date(timeIntervalSince1970: 2), standardDefaults: Data("config".utf8), sharedDefaults: Data(), privateRecords: [], applicationState: [])
        try await store.save(first)
        let restored = try await store.load()
        XCTAssertEqual(restored, first)
        try await store.save(second)
        let previous = try JSONDecoder().decode(ConfigurationSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("configuration.previous.json")))
        XCTAssertEqual(previous, first)
        let latest = try await store.load()
        XCTAssertEqual(latest, second)
    }

    func testShortcutDefaultsRoundTrip() throws {
        let name = "OneBoard.BackupRegression.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "KeyboardShortcuts_screenshot"
        defaults.set("shortcut", forKey: key)
        let data = try ConfigurationSnapshotCodec.encodeDefaults(defaults, keys: ConfigurationSnapshotCodec.standardKeys)
        defaults.removeObject(forKey: key)
        try ConfigurationSnapshotCodec.applyDefaults(data, to: defaults, keys: ConfigurationSnapshotCodec.standardKeys)
        XCTAssertEqual(defaults.string(forKey: key), "shortcut")
    }
}
