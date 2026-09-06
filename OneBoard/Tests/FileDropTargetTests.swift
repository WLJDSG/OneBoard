import AppKit
import XCTest
@testable import OneBoardKit

final class FileDropTargetTests: XCTestCase {
    @MainActor
    func testNativeFinderFileURLsAndPlainTextRejection() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("文件 A.png"), directory.appendingPathComponent("B.pdf")]
        for url in urls { try Data().write(to: url) }
        let items = urls.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        XCTAssertEqual(FileDropTarget.Destination.urls(from: items), urls)
        board.clearContents()
        board.setString("/tmp/not-a-file-drag", forType: .string)
        XCTAssertTrue(FileDropTarget.Destination.urls(board).isEmpty)
    }

    @MainActor
    func testFinderLegacyFilenamePayloadIsAccepted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = [directory.appendingPathComponent("文件 A.png").path, directory.appendingPathComponent("B.pdf").path]
        for path in paths { try Data().write(to: URL(fileURLWithPath: path)) }
        XCTAssertEqual(FileDropTarget.Destination.urls(fromLegacyPropertyList: paths).map(\.path), paths)
    }

    func testNotchShelfAnimationExpandsFromAndCollapsesToScreenTopCenter() {
        let screen = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let expanded = NotchShelfAnimationLayout.expandedFrame(on: screen)
        let collapsed = NotchShelfAnimationLayout.collapsedFrame(on: screen)

        XCTAssertEqual(expanded.size, FileStagingViewModel.notchShelfSize)
        XCTAssertEqual(expanded.midX, screen.midX)
        XCTAssertEqual(expanded.maxY, screen.maxY)
        XCTAssertEqual(collapsed.midX, screen.midX)
        XCTAssertEqual(collapsed.maxY, screen.maxY)
        XCTAssertLessThan(collapsed.width, expanded.width)
        XCTAssertLessThan(collapsed.height, expanded.height)
        XCTAssertGreaterThan(NotchShelfAnimationLayout.showDuration, 0)
        XCTAssertGreaterThan(NotchShelfAnimationLayout.hideDuration, 0)
    }
}
