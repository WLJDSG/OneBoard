import AppKit
import SwiftUI
@testable import OneBoardKit
import XCTest

@MainActor
final class AnnotationServiceTests: XCTestCase {
    func testRenderPreservesSinglePixelStripes() throws {
        let image = makeImage(points: CGSize(width: 64, height: 32), pixels: CGSize(width: 128, height: 64))
        let source = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        for y in 0..<64 {
            for x in 0..<128 { source.setColor(NSColor(deviceRed: x.isMultiple(of: 2) ? 0 : 1, green: x.isMultiple(of: 2) ? 0 : 1, blue: x.isMultiple(of: 2) ? 0 : 1, alpha: 1), atX: x, y: y) }
        }
        XCTAssertEqual(source.colorAt(x: 10, y: 20)?.usingColorSpace(.deviceRGB)?.redComponent, 0)
        let rendered = AnnotationService(baseImage: image).renderToImage(baseImage: image)
        let output = try XCTUnwrap(rendered.representations.first as? NSBitmapImageRep)
        for x in 10..<30 {
            let value = try XCTUnwrap(output.colorAt(x: x, y: 20)?.usingColorSpace(.deviceRGB)).redComponent
            XCTAssertEqual(value, x.isMultiple(of: 2) ? 0 : 1, accuracy: 0.02)
        }
    }

    func testPinnedViewPreservesRetinaPixelStripes() throws {
        let image = makeImage(points: CGSize(width: 64, height: 32), pixels: CGSize(width: 128, height: 64))
        let source = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        for y in 0..<64 {
            for x in 0..<128 {
                let value: CGFloat = x.isMultiple(of: 2) ? 0 : 1
                source.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let rendered = AnnotationService(baseImage: image).renderToImage(baseImage: image)
        let renderer = ImageRenderer(content: PinnedScreenshotView(image: rendered, onClose: {}).frame(width: 64, height: 32))
        renderer.scale = 2
        let output = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        XCTAssertEqual(output.pixelsWide, 128)
        for x in 10..<30 {
            let value = try XCTUnwrap(output.colorAt(x: x, y: 20)?.usingColorSpace(.deviceRGB)).redComponent
            XCTAssertEqual(value, x.isMultiple(of: 2) ? 0 : 1, accuracy: 0.02)
        }
    }

    func testPinnedPanelKeepsSelectionFrame() throws {
        let image = makeImage(points: CGSize(width: 128, height: 64), pixels: CGSize(width: 256, height: 128))
        let source = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        for y in 0..<128 {
            for x in 0..<256 {
                let value: CGFloat = x.isMultiple(of: 2) ? 0 : 1
                source.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let frame = CGRect(x: 100, y: 100, width: 128, height: 64)
        ScreenshotViewModel.shared.pinToScreen(image, preferredFrame: frame)
        let panels = ScreenshotViewModel.shared.pinnedWindows
        let panel = try XCTUnwrap(panels.last)
        defer {
            panel.close()
            ScreenshotViewModel.shared.pinnedWindows.removeAll { $0 === panel }
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.frame.size, frame.size)
        XCTAssertEqual(panel.contentView?.bounds.size, frame.size)
        let content = try XCTUnwrap(panel.contentView)
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if panel.backingScaleFactor == 2 {
            XCTAssertEqual(bitmap.pixelsWide, 256)
            for x in 10..<30 {
                let value = try XCTUnwrap(bitmap.colorAt(x: x, y: 20)?.usingColorSpace(.deviceRGB)).redComponent
                XCTAssertEqual(value, x.isMultiple(of: 2) ? 0 : 1, accuracy: 0.02)
            }
        }

    }

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

    func testNumberedMarkersIncrementFromOne() {
        let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
        let service = AnnotationService(baseImage: image)

        service.addNumber(at: CGPoint(x: 20, y: 20))
        service.addNumber(at: CGPoint(x: 50, y: 50))

        XCTAssertEqual(service.layers.map(\.tool), [.number, .number])
        XCTAssertEqual(service.layers.map(\.numberValue), [1, 2])
    }

    func testRenderNumberedMarkerDrawsColoredBadge() throws {
        let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
        let service = AnnotationService(baseImage: image)
        service.selectedColor = .systemBlue
        service.addNumber(at: CGPoint(x: 50, y: 50))

        let rendered = service.renderToImage(baseImage: image, displaySize: image.size)
        let rep = try XCTUnwrap(rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        var bluePixelCount = 0
        for y in 36...64 {
            for x in 36...64 where isMostlyBlue(rep.colorAt(x: x, y: y)) {
                bluePixelCount += 1
            }
        }
        XCTAssertGreaterThan(bluePixelCount, 300)
    }

    func testUndoAndRedoRestoreLastLayer() {
        let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
        let service = AnnotationService(baseImage: image)

        service.addRectangle(CGRect(x: 1, y: 2, width: 30, height: 40))
        service.addNumber(at: CGPoint(x: 60, y: 60))

        service.undo()
        XCTAssertEqual(service.layers.count, 1)
        XCTAssertTrue(service.canRedo)

        service.redo()
        XCTAssertEqual(service.layers.count, 2)
        XCTAssertEqual(service.layers.last?.tool, .number)
        XCTAssertEqual(service.layers.last?.numberValue, 1)
    }

    func testAddingLayerAfterUndoClearsRedo() {
        let image = makeImage(points: CGSize(width: 100, height: 100), pixels: CGSize(width: 100, height: 100))
        let service = AnnotationService(baseImage: image)

        service.addRectangle(CGRect(x: 1, y: 2, width: 30, height: 40))
        service.addEllipse(CGRect(x: 10, y: 10, width: 20, height: 20))
        service.undo()
        XCTAssertTrue(service.canRedo)

        service.addLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40))

        XCTAssertFalse(service.canRedo)
        service.redo()
        XCTAssertEqual(service.layers.map(\.tool), [.rectangle, .line])
    }

    func testCyclePresetColorMovesThroughPalette() {
        let service = AnnotationService()
        service.selectedColor = .systemRed

        service.cyclePresetColorBackward()

        XCTAssertEqual(service.selectedColor, .white)
    }

    func testIncrementStyleValueUsesSelectedTool() {
        let service = AnnotationService()

        service.selectedTool = .rectangle
        service.lineWidth = 2
        service.incrementStyleValue()
        XCTAssertEqual(service.lineWidth, 3)

        service.selectedTool = .text
        service.fontSize = 18
        service.incrementStyleValue()
        XCTAssertEqual(service.fontSize, 19)

        service.selectedTool = .mosaic
        service.mosaicBlockSize = 6
        service.incrementStyleValue()
        XCTAssertEqual(service.mosaicBlockSize, 8)
    }

    func testTextAndCalloutSizesStayBetweenFifteenAndTwentyFive() {
        let service = AnnotationService()
        for tool in [AnnotationTool.text, .callout] {
            service.selectedTool = tool
            service.fontSize = 18
            service.decrementStyleValue()
            XCTAssertEqual(service.fontSize, 17)
            for _ in 0..<20 { service.decrementStyleValue() }
            XCTAssertEqual(service.fontSize, 15)
            for _ in 0..<20 { service.incrementStyleValue() }
            XCTAssertEqual(service.fontSize, 25)
            service.decrementStyleValue()
            XCTAssertEqual(service.fontSize, 24)
        }
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

    private func isMostlyBlue(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > 0.45 && color.redComponent < 0.45
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
