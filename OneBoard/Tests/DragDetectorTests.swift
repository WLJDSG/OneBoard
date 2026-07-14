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

    func testSupportedDraggedFileURLsOnlyAcceptRegularFiles() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let textFile = temporaryDirectory.appendingPathComponent("document.txt")
        let archiveFile = temporaryDirectory.appendingPathComponent("archive.zip")
        let appBundle = temporaryDirectory.appendingPathComponent("Example.app", isDirectory: true)

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        XCTAssertTrue(FileManager.default.createFile(atPath: textFile.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: archiveFile.path, contents: Data()))
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)

        XCTAssertEqual(
            DragDetector.supportedDraggedFileURLs([textFile, archiveFile, temporaryDirectory, appBundle]),
            [textFile, archiveFile]
        )
    }

    func testFileURLTypeWithoutReadableURLsDoesNotConfirmDrag() {
        XCTAssertFalse(DragDetector.canConfirmFileDrag(types: [.fileURL], urls: []))
    }
}
