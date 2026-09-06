import AppKit
@testable import OneBoardKit
import XCTest

final class DragDetectorTests: XCTestCase {
    func testPreviousFileDragCannotConfirmLaterWindowDrag() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("test".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        board.writeObjects([file as NSURL])
        let detector = DragDetector(pasteboard: board)
        XCTAssertFalse(detector.isDraggingSupportedContent, "启动时遗留的文件不能确认新拖拽")
        board.clearContents()
        board.writeObjects([file as NSURL])
        XCTAssertTrue(detector.isDraggingSupportedContent)
        XCTAssertTrue(detector.isDraggingSupportedContent, "同一拖拽后续帧保持有效")
        detector.finishCurrentDrag()
        XCTAssertFalse(detector.isDraggingSupportedContent, "松手后拖动窗口不能复用旧文件")
        board.clearContents()
        board.writeObjects([file as NSURL])
        XCTAssertTrue(detector.isDraggingSupportedContent, "再次拖动同一文件仍有效")
    }

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
