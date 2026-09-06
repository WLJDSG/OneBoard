import AppKit
import XCTest
@testable import OneBoardKit

@MainActor
final class MosaicPixelsTests: XCTestCase {
    func testResizingRegionKeepsOverlappingSquarePixelsStable() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 120,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<120 {
            for x in 0..<160 {
                bitmap.setColor(NSColor(deviceRed: CGFloat(x) / 160, green: CGFloat(y) / 120, blue: 0.2, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: CGSize(width: 80, height: 60))
        image.addRepresentation(bitmap)
        let first = try XCTUnwrap(MosaicPixels.make(image: image, displaySize: image.size,
            rect: CGRect(x: 3, y: 5, width: 35, height: 27), blockSize: 10))
        let second = try XCTUnwrap(MosaicPixels.make(image: image, displaySize: image.size,
            rect: CGRect(x: 3, y: 5, width: 48, height: 39), blockSize: 10))
        XCTAssertEqual(first.width, 70)
        XCTAssertEqual(first.height, 54)
        let a = NSBitmapImageRep(cgImage: first), b = NSBitmapImageRep(cgImage: second)
        for y in stride(from: 3, to: 50, by: 5) {
            for x in stride(from: 3, to: 65, by: 5) {
                let c = try XCTUnwrap(a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let d = try XCTUnwrap(b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(c.redComponent, d.redComponent, accuracy: 0.01)
                XCTAssertEqual(c.greenComponent, d.greenComponent, accuracy: 0.01)
                XCTAssertEqual(c.alphaComponent, 1, accuracy: 0.01)
            }
        }
        // 同一个 10pt 方格内，水平和垂直均为同一颜色。
        XCTAssertEqual(a.colorAt(x: 16, y: 12), a.colorAt(x: 30, y: 26))
    }
}
