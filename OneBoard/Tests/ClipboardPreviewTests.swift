import XCTest
import AppKit
import SwiftUI
@testable import OneBoardKit

final class ClipboardPreviewTests: XCTestCase {
    @MainActor
    func testFilePreviewCanBeRepeatedlyReplacedByText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oneboard-preview-\(UUID().uuidString).txt")
        try Data("file preview".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let hosting = NSHostingView(rootView: AnyView(Text("文本")))
        hosting.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        for _ in 0..<20 {
            hosting.rootView = AnyView(ClipboardFilePreview(url: url))
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 10_000_000)
            hosting.rootView = AnyView(Text("文本"))
            hosting.layoutSubtreeIfNeeded()
        }
    }
    @MainActor
    func testLargeImageUsesBoundedCachedThumbnail() async throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2048, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let entry = ClipboardEntry(id: 1, contentType: "image", data: data)
        let firstResult = await ClipboardThumbnailCache.image(for: entry)
        let first = try XCTUnwrap(firstResult)
        XCTAssertEqual(first.size, NSSize(width: 56, height: 28))
        let second = await ClipboardThumbnailCache.image(for: entry)
        XCTAssertTrue(first === second)
        let invalid = await ClipboardThumbnailCache.image(for: ClipboardEntry(contentType: "image", data: Data()))
        XCTAssertNil(invalid)
    }

    func testLongTextPreviewWorkIsBounded() {
        let text = String(repeating: "剪贴板内容\n", count: 100_000)
        let entry = ClipboardEntry(contentType: "text", plainText: text, data: Data())
        let start = Date()
        for _ in 0..<100 { XCTAssertLessThanOrEqual(entry.previewText.count, 100) }
        print("Clipboard preview 100 iterations: \(Date().timeIntervalSince(start)) seconds")
    }
    func testPreviewPreservesUnicodeAndReplacesNewlines() {
        let entry = ClipboardEntry(contentType: "text", plainText: "你好\n世界👨‍👩‍👧‍👦", data: Data())
        XCTAssertEqual(entry.previewText, "你好 世界👨‍👩‍👧‍👦")
    }
}
