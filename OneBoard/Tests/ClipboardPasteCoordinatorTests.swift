import XCTest
@testable import OneBoard

@MainActor
final class ClipboardPasteCoordinatorTests: XCTestCase {
    func testPasteRunsInsideMonitorIgnoreScope() async {
        let monitor = PasteboardMonitor.shared
        let entry = ClipboardEntry(
            contentType: PasteboardTypeMapper.ContentType.text.rawValue,
            plainText: "hello",
            data: Data("hello".utf8),
            createdAt: Date()
        )
        var observedIsPastingDuringWrite = false
        var didClose = false
        var didPaste = false

        let coordinator = ClipboardPasteCoordinator(
            monitor: monitor,
            pasteboardWriter: { _ in observedIsPastingDuringWrite = monitor.isPasting },
            targetAppProvider: { nil },
            closeClipboardWindow: { didClose = true },
            pasteAction: { _ in didPaste = true }
        )

        coordinator.paste(entry)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(observedIsPastingDuringWrite)
        XCTAssertTrue(didClose)
        XCTAssertTrue(didPaste)
        XCTAssertFalse(monitor.isPasting)
    }
}
