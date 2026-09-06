import XCTest
import AppKit
@testable import OneBoardKit

@MainActor
final class QuickLaunchMigrationTests: XCTestCase {
    func testMigrationPreservesOccupiedSlotsAndIsIdempotent() throws {
        let suite = "QuickLaunchTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = ["A": QuickLaunchBinding(kind: "app", target: "/Applications/Example.app", title: "Example"),
                        "-": QuickLaunchBinding(kind: "web", target: "https://example.com", title: "网页")]
        defaults.set(try JSONEncoder().encode(existing), forKey: QuickLaunchBindings.storageKey)
        QuickLaunchBindings.migrate(defaults: defaults)
        let migrated = QuickLaunchBindings.load(defaults: defaults)
        XCTAssertEqual(migrated["A"]?.target, existing["A"]?.target)
        XCTAssertTrue(migrated.values.contains { $0.target == "https://example.com" })
        XCTAssertNil(migrated["-"])
        for tool in QuickLaunchBindings.tools.prefix(7) {
            XCTAssertEqual(migrated.values.filter { $0.kind == "tool" && $0.target == tool.0 }.count, 1)
        }
        let data = defaults.data(forKey: QuickLaunchBindings.storageKey)
        QuickLaunchBindings.migrate(defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: QuickLaunchBindings.storageKey), data)
    }

    func testMenuImagesShareHeightAndUptimeIncludesDays() {
        XCTAssertEqual(MenuBarManager.menuSymbol("calendar")?.size.height, 18)
        XCTAssertEqual(MenuBarManager.networkImage(upload: 1048576, download: 1024).size.height, 18)
        XCTAssertEqual(MacStatusModel.uptimeText(23 * 3600), "23 小时")
        XCTAssertEqual(MacStatusModel.uptimeText(24 * 3600), "1 天 0 小时")
        XCTAssertEqual(MacStatusModel.uptimeText(49 * 3600), "2 天 1 小时")
    }
}
