import AppKit
import XCTest
@testable import OneBoardKit

final class FileDropTargetTests: XCTestCase {
    @MainActor
    func testNativeFinderFileURLsAndPlainTextRejection() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/文件 A.png"), URL(fileURLWithPath: "/tmp/B.pdf")]
        board.writeObjects(urls as [NSURL])
        XCTAssertEqual(FileDropTarget.Destination.urls(board), urls)
        board.clearContents()
        board.setString("/tmp/not-a-file-drag", forType: .string)
        XCTAssertTrue(FileDropTarget.Destination.urls(board).isEmpty)
    }
}
