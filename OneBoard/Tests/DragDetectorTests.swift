import AppKit
@testable import OneBoard
import XCTest

final class DragDetectorTests: XCTestCase {
    func testDragTypeFilteringOnlyAcceptsFileURLs() {
        XCTAssertTrue(DragDetector.supportsDraggedFileTypes([.fileURL]))
        XCTAssertTrue(DragDetector.supportsDraggedFileTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType")]))

        XCTAssertFalse(DragDetector.supportsDraggedFileTypes([.png]))
        XCTAssertFalse(DragDetector.supportsDraggedFileTypes([.tiff]))
        XCTAssertFalse(DragDetector.supportsDraggedFileTypes([.string]))
    }
}
