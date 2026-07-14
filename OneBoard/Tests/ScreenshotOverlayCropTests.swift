import CoreGraphics
@testable import OneBoardKit
import XCTest

final class ScreenshotOverlayCropTests: XCTestCase {
    func testScreenRectKeepsTopSelectionAtTopOfScreen() {
        let screenFrame = CGRect(x: -1440, y: 120, width: 1440, height: 900)
        let overlayRect = CGRect(x: 100, y: 700, width: 400, height: 120)

        let result = ScreenshotCropMapper.screenRect(
            forOverlayRect: overlayRect,
            screenFrame: screenFrame
        )

        XCTAssertEqual(result, CGRect(x: -1340, y: 820, width: 400, height: 120))
    }

    func testCropRectStillFlipsYForCGImagePixels() {
        let result = ScreenshotCropMapper.cropRect(
            forOverlayRect: CGRect(x: 100, y: 700, width: 400, height: 120),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        XCTAssertEqual(result, CGRect(x: 200, y: 160, width: 800, height: 240))
    }

    func testCropRectClampsSelectionToCapturedImageBounds() {
        let crop = ScreenshotCropMapper.cropRect(
            forOverlayRect: CGRect(x: 980, y: 700, width: 80, height: 80),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 750),
            imagePixelSize: CGSize(width: 2000, height: 1500)
        )

        XCTAssertEqual(crop, CGRect(x: 1960, y: 0, width: 40, height: 100))
    }
}
