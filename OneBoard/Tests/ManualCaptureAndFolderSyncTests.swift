import AppKit
import XCTest
@testable import OneBoardKit

final class ManualCaptureAndFolderSyncTests: XCTestCase {
    func testSparseDocumentScrollIsRecognized() throws {
        func document(_ offset: Int) -> NSImage {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 960, bitsPerPixel: 32)!
            for y in 0..<200 { for x in 0..<240 {
                let line = [21, 39, 72, 103, 141, 187, 224].contains(y + offset)
                let v: CGFloat = line && x > 25 && x < 210 ? 0 : 1
                rep.setColor(NSColor(deviceRed: v, green: v, blue: v, alpha: 1), atX: x, y: y)
            } }
            let image = NSImage(size: NSSize(width: 240, height: 200)); image.addRepresentation(rep); return image
        }
        let shift = try XCTUnwrap(LongScreenshotStitcher.verticalShift(document(0), document(23)))
        XCTAssertEqual(shift, 23, accuracy: 1)
    }
    func testVariableScrollOverlapAndAppend() throws {
        let first = frame(offset: 0)
        for offset in [7, 23, 48] {
            let next = frame(offset: offset)
            let shift = try XCTUnwrap(LongScreenshotStitcher.verticalShift(first, next))
            XCTAssertEqual(shift, CGFloat(offset), accuracy: 0.1)
            let result = LongScreenshotStitcher.append(first, frame: next, height: shift)
            XCTAssertEqual(result.size.height, 100 + CGFloat(offset))
        }
    }

    private func frame(offset: Int) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 320, bitsPerPixel: 32)!
        for y in 0..<100 {
            for x in 0..<80 {
                let v = CGFloat(((y + offset) * 7919 + x * 104729 + (y + offset) * x * 37) % 251) / 250
                bitmap.setColor(NSColor(deviceRed: v, green: v, blue: v, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: 80, height: 100))
        image.addRepresentation(bitmap)
        return image
    }

    func testEncryptedFolderRoundTripAndWrongKey() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = Data(repeating: 27, count: 32)
        let snapshot = ConfigurationSnapshot(schema: 1, modifiedAt: Date(timeIntervalSince1970: 1234), standardDefaults: Data("secret-config".utf8), sharedDefaults: Data(), privateRecords: [], applicationState: [])
        let store = FolderConfigurationStore(folder: folder, key: key)
        try await store.save(snapshot)
        let restored = try await store.load()
        XCTAssertEqual(restored, snapshot)
        let data = try Data(contentsOf: folder.appendingPathComponent("OneBoard.configuration.encrypted"))
        XCTAssertNil(data.range(of: Data("secret-config".utf8)))
        XCTAssertThrowsError(try FolderConfigurationStore.decrypt(data, key: Data(repeating: 28, count: 32)))
        var modified = data
        modified[0] ^= 1
        XCTAssertThrowsError(try FolderConfigurationStore.decrypt(modified, key: key))
    }

    func testClipboardClassification() {
        func item(_ type: String, _ text: String = "") -> ClipboardEntry { ClipboardEntry(contentType: type, plainText: text, data: Data()) }
        XCTAssertTrue(ClipboardCategory.link.matches(item("text", "https://example.com/test")))
        XCTAssertFalse(ClipboardCategory.link.matches(item("text", "https://example.com hello")))
        XCTAssertTrue(ClipboardCategory.color.matches(item("text", "#ABCDEF")))
        XCTAssertTrue(ClipboardCategory.file.matches(item("fileURL")))
        XCTAssertFalse(ClipboardCategory.text.matches(item("image")))
        XCTAssertFalse(ClipboardCategory.text.matches(item("text", "https://example.com")))
    }
}
