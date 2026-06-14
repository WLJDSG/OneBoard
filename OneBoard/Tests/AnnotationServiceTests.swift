import AppKit
@testable import OneBoard
import XCTest

@MainActor
final class AnnotationServiceTests: XCTestCase {
    func testRenderKeepsSourcePixelDimensionsForRetinaImages() {
        let image = makeImage(points: CGSize(width: 100, height: 50), pixels: CGSize(width: 200, height: 100))
        let service = AnnotationService(baseImage: image)
        let displaySize = CGSize(width: 80, height: 40)

        let rendered = service.renderToImage(baseImage: image, displaySize: displaySize)
        let rep = rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first

        XCTAssertEqual(rep?.pixelsWide, 200)
        XCTAssertEqual(rep?.pixelsHigh, 100)
        XCTAssertEqual(rendered.size, displaySize)
    }

    func testRenderMapsScaledDisplayAnnotationRectFromTopLeftCanvasToPixelSpace() {
        let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 200, height: 200))
        let service = AnnotationService(baseImage: image)
        service.selectedColor = .systemRed
        service.lineWidth = 2
        service.addRectangle(CGRect(x: 5, y: 10, width: 15, height: 20))

        let rendered = service.renderToImage(baseImage: image, displaySize: CGSize(width: 50, height: 50))
        let rep = rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first

        XCTAssertTrue(isMostlyRed(rep?.colorAt(x: 20, y: 40)))
        XCTAssertFalse(isMostlyRed(rep?.colorAt(x: 20, y: 160)))
    }

    func testPNGDataUsesRenderedBitmapPixelsWithoutAddingTransparentCanvas() throws {
        let image = makeImage(points: CGSize(width: 100, height: 50), pixels: CGSize(width: 200, height: 100))
        let service = AnnotationService(baseImage: image)

        let rendered = service.renderToImage(baseImage: image, displaySize: CGSize(width: 80, height: 40))
        let renderedRep = try XCTUnwrap(rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        XCTAssertTrue(isMostlyWhite(renderedRep.colorAt(x: 5, y: 5)))
        XCTAssertTrue(isMostlyWhite(renderedRep.colorAt(x: 195, y: 95)))

        let data = try XCTUnwrap(rendered.pngData)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(rep.pixelsWide, 200)
        XCTAssertEqual(rep.pixelsHigh, 100)
        XCTAssertTrue(isMostlyWhite(rep.colorAt(x: 5, y: 5)))
        XCTAssertTrue(isMostlyWhite(rep.colorAt(x: 195, y: 95)))
    }

    func testRenderTextKeepsGlyphsFacingLeftToRight() throws {
        let image = makeImage(points: CGSize(width: 100, height: 60), pixels: CGSize(width: 100, height: 60))
        let service = AnnotationService(baseImage: image)
        service.selectedColor = .systemRed
        service.addText(in: CGRect(x: 8, y: 8, width: 54, height: 36), text: "L", fontSize: 30)

        let rendered = service.renderToImage(baseImage: image, displaySize: image.size)
        let rep = try XCTUnwrap(rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        let redPixels = redPixelBounds(in: rep)
        XCTAssertLessThan(redPixels.minX, 28)
        XCTAssertLessThan(redPixels.midX, 40)
    }

    private func makeImage(points: CGSize, pixels: CGSize) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width),
            pixelsHigh: Int(pixels.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = points
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        CGRect(origin: .zero, size: pixels).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: points)
        image.addRepresentation(rep)
        return image
    }

    private func isMostlyRed(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.deviceRGB) else { return false }
        return color.redComponent > 0.75 && color.greenComponent < 0.35 && color.blueComponent < 0.35
    }

    private func isMostlyWhite(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.deviceRGB) else { return false }
        return color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9 && color.alphaComponent > 0.9
    }

    private func redPixelBounds(in rep: NSBitmapImageRep) -> CGRect {
        var minX = rep.pixelsWide
        var minY = rep.pixelsHigh
        var maxX = 0
        var maxY = 0

        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where isMostlyRed(rep.colorAt(x: x, y: y)) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
