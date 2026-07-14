import AppKit
@testable import OneBoardKit
import XCTest

final class ScreenshotSelectionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)

    func testMovingSelectionClampsToScreenBounds() {
        let result = ScreenshotSelectionGeometry.moved(
            CGRect(x: 800, y: 500, width: 180, height: 160),
            by: CGSize(width: 100, height: 100),
            inside: bounds
        )

        XCTAssertEqual(result, CGRect(x: 820, y: 540, width: 180, height: 160))
    }

    func testTopLeftResizeMovesOnlyTopAndLeftEdges() {
        let result = ScreenshotSelectionGeometry.resized(
            CGRect(x: 200, y: 200, width: 300, height: 200),
            handle: .topLeft,
            to: CGPoint(x: 150, y: 460),
            inside: bounds,
            minimumSize: CGSize(width: 24, height: 24)
        )

        XCTAssertEqual(result, CGRect(x: 150, y: 200, width: 350, height: 260))
    }

    func testAllResizeHandlesChangeExpectedEdges() {
        let rect = CGRect(x: 200, y: 200, width: 300, height: 200)
        let cases: [(ScreenshotResizeHandle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 150, y: 450), CGRect(x: 150, y: 200, width: 350, height: 250)),
            (.top, CGPoint(x: 350, y: 450), CGRect(x: 200, y: 200, width: 300, height: 250)),
            (.topRight, CGPoint(x: 550, y: 450), CGRect(x: 200, y: 200, width: 350, height: 250)),
            (.right, CGPoint(x: 550, y: 300), CGRect(x: 200, y: 200, width: 350, height: 200)),
            (.bottomRight, CGPoint(x: 550, y: 150), CGRect(x: 200, y: 150, width: 350, height: 250)),
            (.bottom, CGPoint(x: 350, y: 150), CGRect(x: 200, y: 150, width: 300, height: 250)),
            (.bottomLeft, CGPoint(x: 150, y: 150), CGRect(x: 150, y: 150, width: 350, height: 250)),
            (.left, CGPoint(x: 150, y: 300), CGRect(x: 150, y: 200, width: 350, height: 200)),
        ]

        for (handle, point, expected) in cases {
            XCTAssertEqual(
                ScreenshotSelectionGeometry.resized(
                    rect,
                    handle: handle,
                    to: point,
                    inside: bounds,
                    minimumSize: CGSize(width: 24, height: 24)
                ),
                expected,
                "Unexpected geometry for \(handle)"
            )
        }
    }

    func testResizeHonorsMinimumSize() {
        let result = ScreenshotSelectionGeometry.resized(
            CGRect(x: 200, y: 200, width: 300, height: 200),
            handle: .bottomLeft,
            to: CGPoint(x: 490, y: 390),
            inside: bounds,
            minimumSize: CGSize(width: 24, height: 24)
        )

        XCTAssertEqual(result, CGRect(x: 476, y: 376, width: 24, height: 24))
    }

    func testClickOutsideExistingSelectionStartsNewSelection() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))

        model.begin(at: CGPoint(x: 700, y: 500), bounds: bounds)
        model.update(to: CGPoint(x: 850, y: 620), bounds: bounds)
        model.end(at: CGPoint(x: 850, y: 620), bounds: bounds)

        XCTAssertEqual(model.rect, CGRect(x: 700, y: 500, width: 150, height: 120))
        XCTAssertEqual(model.phase, .adjusting)
    }

    func testDraggingInsideSelectionMovesIt() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))

        model.begin(at: CGPoint(x: 150, y: 150), bounds: bounds)
        model.update(to: CGPoint(x: 250, y: 225), bounds: bounds)
        model.end(at: CGPoint(x: 250, y: 225), bounds: bounds)

        XCTAssertEqual(model.rect, CGRect(x: 200, y: 175, width: 200, height: 150))
    }

    func testLockReturnsSelectionOnlyOnceAndPreventsChanges() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))

        XCTAssertEqual(model.lock(), model.rect)
        XCTAssertNil(model.lock())
        model.begin(at: CGPoint(x: 150, y: 150), bounds: bounds)
        model.update(to: CGPoint(x: 400, y: 400), bounds: bounds)
        model.end(at: CGPoint(x: 400, y: 400), bounds: bounds)

        XCTAssertEqual(model.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(model.phase, .locked)
    }

}
