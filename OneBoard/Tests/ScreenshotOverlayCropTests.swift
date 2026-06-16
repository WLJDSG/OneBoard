import CoreGraphics
@testable import OneBoard
import XCTest

final class ScreenshotOverlayCropTests: XCTestCase {
    func testCropRectClampsSelectionToCapturedImageBounds() {
        let crop = ScreenshotCropMapper.cropRect(
            forOverlayRect: CGRect(x: 980, y: 700, width: 80, height: 80),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 750),
            imagePixelSize: CGSize(width: 2000, height: 1500)
        )

        XCTAssertEqual(crop, CGRect(x: 1960, y: 0, width: 40, height: 100))
    }
}
