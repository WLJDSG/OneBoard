import AppKit
import SwiftUI
import XCTest
@testable import OneBoardKit

@MainActor
final class FileShelfDropSessionTests: XCTestCase {
    func testHostingDestinationCompletesNativeDropCallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("native drop".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects([url as NSURL]))
        var received: [URL] = []
        let host = FileShelfHostingView(rootView: FileDropTarget(targeted: .constant(false)) { received = $0 }
            .frame(width: 440, height: 220))
        let window = NSWindow(contentRect: CGRect(x: 200, y: 100, width: 440, height: 220), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let session = ShelfDraggingInfo(board: board, window: window)
        XCTAssertEqual(host.draggingEntered(session), .copy)
        XCTAssertTrue(host.prepareForDragOperation(session))
        XCTAssertTrue(host.performDragOperation(session))
        XCTAssertEqual(received, [url])
    }
}

@MainActor
private final class ShelfDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation = CGPoint(x: 220, y: 110)
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(board: NSPasteboard, window: NSWindow) { draggingPasteboard = board; draggingDestinationWindow = window }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
