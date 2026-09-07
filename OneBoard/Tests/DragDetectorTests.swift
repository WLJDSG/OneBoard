import AppKit
@testable import OneBoardKit
import XCTest

final class DragDetectorTests: XCTestCase {
    func testDragDetectionDoesNotRequireAccessToFile() {
        let inaccessible = URL(fileURLWithPath: "/unavailable-folder/document.txt", isDirectory: false)
        XCTAssertTrue(DragDetector.canConfirmFileDrag(types: [.fileURL], urls: [inaccessible]),
                      "拖动检测只能检查载荷，不能在用户投放前读取受保护目录")
        XCTAssertFalse(DragDetector.canConfirmFileDrag(types: [.fileURL], urls: [URL(fileURLWithPath: "/Example.app", isDirectory: true)]))
        XCTAssertFalse(DragDetector.canConfirmFileDrag(types: [.fileURL], urls: [URL(string: "https://example.com/file.txt")!]))
    }
    func testPreviousFileDragCannotConfirmLaterWindowDrag() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("test".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let detector = DragDetector(pasteboard: board)
        XCTAssertFalse(detector.isDraggingSupportedContent, "启动时遗留的文件不能确认新拖拽")
        XCTAssertTrue(detector.updateDragState(changeCount: board.changeCount + 1, types: [.fileURL], urls: [file]))
        XCTAssertTrue(detector.updateDragState(changeCount: board.changeCount + 1, types: [.fileURL], urls: []), "同一拖拽后续帧保持有效")
        detector.finishCurrentDrag()
        XCTAssertFalse(detector.isDraggingSupportedContent, "松手后拖动窗口不能复用旧文件")
        XCTAssertTrue(detector.updateDragState(changeCount: board.changeCount + 1, types: [.fileURL], urls: [file]), "再次拖动同一文件仍有效")
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

    func testFileDragRevealsShelfImmediatelyAndOnlyOncePerDrag() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let detector = DragDetector(pasteboard: board)
        XCTAssertTrue(detector.updateDragState(changeCount: board.changeCount + 1, types: [.fileURL], urls: [file]))
        XCTAssertTrue(detector.shouldRevealShelfForCurrentDrag(), "文件拖拽首帧就应显示暂存区")
        XCTAssertFalse(detector.shouldRevealShelfForCurrentDrag(), "同一次拖拽不能重复弹出")
        detector.finishCurrentDrag()
        XCTAssertTrue(detector.updateDragState(changeCount: board.changeCount + 1, types: [.fileURL], urls: [file]))
        XCTAssertTrue(detector.shouldRevealShelfForCurrentDrag(), "下一次文件拖拽应再次显示")
    }
}
