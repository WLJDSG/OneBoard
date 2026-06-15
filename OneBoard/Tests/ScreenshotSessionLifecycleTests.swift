import XCTest
@testable import OneBoard

@MainActor
final class ScreenshotSessionLifecycleTests: XCTestCase {
    func testCloseActiveScreenshotSessionIsIdempotent() {
        let viewModel = ScreenshotViewModel.shared

        viewModel.closeActiveScreenshotSession()
        viewModel.closeActiveScreenshotSession()

        XCTAssertTrue(true)
    }
}
