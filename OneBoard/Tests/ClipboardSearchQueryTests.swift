@testable import OneBoard
import XCTest

final class ClipboardSearchQueryTests: XCTestCase {
    func testChineseSearchUsesSubstringLikePattern() {
        let plan = ClipboardSearchQuery.plan(for: "测试")

        XCTAssertEqual(plan.sqlPredicate, "clipboard_history.plainText LIKE ? COLLATE NOCASE")
        XCTAssertEqual(plan.arguments, ["%测试%"])
    }

    func testWhitespaceSeparatedSearchRequiresEveryTermAsSubstring() {
        let plan = ClipboardSearchQuery.plan(for: "18 测试 通过")

        XCTAssertEqual(
            plan.sqlPredicate,
            "clipboard_history.plainText LIKE ? COLLATE NOCASE AND clipboard_history.plainText LIKE ? COLLATE NOCASE AND clipboard_history.plainText LIKE ? COLLATE NOCASE"
        )
        XCTAssertEqual(plan.arguments, ["%18%", "%测试%", "%通过%"])
    }
}
