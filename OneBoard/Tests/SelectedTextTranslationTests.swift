import XCTest
@testable import OneBoardKit

@MainActor
final class SelectedTextTranslationTests: XCTestCase {
    func testMissingPermissionRequestsAuthorizationBeforeReading() async {
        var requested = false
        await SelectedTextTranslation.run(hasPermission: false, requestPermission: { requested = true },
            readText: { XCTFail("未授权不能读取选区"); return "text" },
            translate: { _ in XCTFail("未授权不能打开翻译窗口") })
        XCTAssertTrue(requested)
    }
    func testEmptySelectionDoesNothing() async {
        await SelectedTextTranslation.run(hasPermission: true, requestPermission: { XCTFail() },
            readText: { " \n " }, translate: { _ in XCTFail("空选区不能打开窗口") })
    }
    func testSelectedTextTranslatesImmediately() async {
        var result = ""
        await SelectedTextTranslation.run(hasPermission: true, requestPermission: { XCTFail() },
            readText: { "  hello  " }, translate: { result = $0 })
        XCTAssertEqual(result, "hello")
    }
}
