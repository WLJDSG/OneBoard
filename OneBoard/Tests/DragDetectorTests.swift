import AppKit
@testable import OneBoardKit
import XCTest

final class DragDetectorTests: XCTestCase {
    func testPollingFallbackRemainsEnabledWithoutInputMonitoringPermission() {
        let strategy = DragDetector.startupStrategy(inputMonitoringGranted: false)

        XCTAssertTrue(strategy.startPolling)
        XCTAssertFalse(strategy.startEventTap)
    }

    func testDragTypeFilteringOnlyAcceptsFileURLs() {
        XCTAssertTrue(DragDetector.supportsDraggedFileTypes([.fileURL]))
        XCTAssertTrue(DragDetector.supportsDraggedFileTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType")]))

        XCTAssertFalse(DragDetector.supportsDraggedFileTypes([.png]))
        XCTAssertFalse(DragDetector.supportsDraggedFileTypes([.tiff]))
        XCTAssertFalse(DragDetector.supportsDraggedFileTypes([.string]))
    }

    func testDragConfirmationAcceptsFileTypeWhenPasteboardChangeCountIsStable() {
        let lastSeenChangeCount = 12

        XCTAssertTrue(DragDetector.canConfirmFileDrag(
            types: [.fileURL],
            changeCount: lastSeenChangeCount,
            lastSeenChangeCount: lastSeenChangeCount
        ))

        XCTAssertTrue(DragDetector.canConfirmFileDrag(
            types: [.fileURL],
            changeCount: lastSeenChangeCount + 1,
            lastSeenChangeCount: lastSeenChangeCount
        ))
    }
}
