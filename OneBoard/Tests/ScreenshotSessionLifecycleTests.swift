import XCTest
@testable import OneBoardKit

@MainActor
final class ScreenshotSessionLifecycleTests: XCTestCase {
    func testRetinaScreenshotUsesLogicalSelectionSize() {
        let selection = CGRect(x: 120, y: 240, width: 900, height: 360)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let size = ScreenshotPresentationLayout.displayedSize(
            selectionRect: selection,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(size, selection.size)
    }

    func testUnscaledScreenshotKeepsSelectionOrigin() {
        let selection = CGRect(x: 120, y: 240, width: 640, height: 360)

        let origin = ScreenshotPresentationLayout.origin(
            selectionRect: selection,
            displayedSize: selection.size,
            scale: 1
        )

        XCTAssertEqual(origin, selection.origin)
    }

    func testOCRPanelSizeStaysInsideSmallScreen() {
        let size = OCRBubbleLayout.panelSize(in: CGRect(x: 0, y: 0, width: 360, height: 260))

        XCTAssertLessThanOrEqual(size.width, 328)
        XCTAssertLessThanOrEqual(size.height, 228)
    }

    func testFloatingPanelsUseStableSizes() {
        XCTAssertEqual(FileStagingViewModel.shelfSize, CGSize(width: 348, height: 434))
        XCTAssertEqual(TodoSlidePanelWindowManager.panelSize, CGSize(width: 340, height: 540))
    }

    func testCloseActiveScreenshotSessionIsIdempotent() {
        let viewModel = ScreenshotViewModel.shared

        viewModel.closeActiveScreenshotSession()
        viewModel.closeActiveScreenshotSession()

        XCTAssertTrue(true)
    }
}
