import AppKit
import XCTest
@testable import OneBoardKit

final class ScreenshotExperienceRegressionTests: XCTestCase {
    @MainActor
    func testFontSizeClampsLegacyValuesToCurrentRange() {
        let service = AnnotationService()
        service.selectedTool = .text
        service.fontSize = 30
        service.incrementStyleValue()
        XCTAssertEqual(service.fontSize, 25)
        service.decrementStyleValue()
        XCTAssertEqual(service.fontSize, 24)
        service.fontSize = 12
        service.decrementStyleValue()
        XCTAssertEqual(service.fontSize, 15)
        service.incrementStyleValue()
        XCTAssertEqual(service.fontSize, 16)
    }

    func testStationaryRepeatedRowsWithLiveBadgeDoNotAppend() {
        let first = repeatedPage(changed: false)
        let second = repeatedPage(changed: true)
        let shift = LongScreenshotStitcher.verticalShift(first, second)
        XCTAssertTrue(shift == nil || shift == 0, "局部状态变化不能产生滚动：\(String(describing: shift))")
    }

    private func repeatedPage(changed: Bool) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 240, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 480, bitsPerPixel: 32)!
        for y in 0..<240 { for x in 0..<120 {
            var value: CGFloat = y % 24 < 3 && x > 12 && x < 108 ? 0.15 : 1
            if changed && y > 200 && y < 215 && x > 40 && x < 80 { value = 0.5 }
            rep.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
        } }
        let image = NSImage(size: CGSize(width: 120, height: 240)); image.addRepresentation(rep); return image
    }
}

extension ScreenshotExperienceRegressionTests {
    func testSamplingUsesSRGBAndRetinaScreenCoordinates() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 16, bitsPerPixel: 32))
        for y in 0..<4 { for x in 0..<4 { bitmap.setColor(NSColor(deviceRed: y < 2 ? 1 : 0, green: 0, blue: y < 2 ? 0 : 1, alpha: 1), atX: x, y: y) } }
        let image = NSImage(size: CGSize(width: 2, height: 2)); image.addRepresentation(bitmap)
        let surface = try XCTUnwrap(ScreenshotColorSurface(image: image, frame: CGRect(x: -100, y: 40, width: 2, height: 2)))
        let top = try XCTUnwrap(surface.sample(at: CGPoint(x: -99.5, y: 41.5)))
        let bottom = try XCTUnwrap(surface.sample(at: CGPoint(x: -99.5, y: 40.5)))
        XCTAssertGreaterThan(top.red, 240); XCTAssertLessThan(top.blue, 20)
        XCTAssertGreaterThan(bottom.blue, 240); XCTAssertLessThan(bottom.red, 20)
        XCTAssertNil(surface.sample(at: .zero))
        XCTAssertEqual(ScreenshotSampledColor(red: 1, green: 20, blue: 255).text, "RGB(1, 20, 255)")
    }

    @MainActor
    func testCalloutKeepsTargetWhenMovingLabelAndUndoesTogether() throws {
        let service = AnnotationService()
        let target = CGRect(x: 20, y: 20, width: 100, height: 80)
        let label = CalloutGeometry.textRect(for: target, canvas: CGSize(width: 600, height: 400), fontSize: 18)
        service.addCallout(target: target, label: label, text: "这里需要修改")
        let layer = try XCTUnwrap(service.layers.first)
        service.updateTextLayer(id: layer.id, rect: label.offsetBy(dx: 40, dy: 10))
        XCTAssertEqual(service.layers.first?.calloutRect, target)
        let connector = CalloutGeometry.connector(target: target, label: label)
        XCTAssertEqual(connector.end.y, target.maxY, accuracy: 0.01)
        service.undo(); XCTAssertTrue(service.layers.isEmpty)
        service.redo(); XCTAssertEqual(service.layers.count, 1)
        XCTAssertEqual(service.layers.first?.text, "这里需要修改")
    }

    func testPopupCandidatesPreserveFrontToBackOrdering() {
        func info(_ rect: CGRect, layer: Int, alpha: Double = 1) -> [String: Any] {
            [kCGWindowBounds as String: rect.dictionaryRepresentation, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha]
        }
        let popup = CGRect(x: 200, y: 200, width: 220, height: 180)
        let back = CGRect(x: 100, y: 100, width: 600, height: 500)
        let frames = ScreenshotWindowCandidate.frames(from: [info(back, layer: 0, alpha: 0), info(popup, layer: 101), info(back, layer: 0)], primaryScreenHeight: 900)
        XCTAssertEqual(frames, [popup, back].map { ScreenshotWindowCandidate.appKitRect(from: $0, primaryScreenHeight: 900) })
    }

    func testDockFullScreenSurfaceDoesNotMaskAppOrCalendarCandidates() {
        func info(_ rect: CGRect, layer: Int, pid: Int32) -> [String: Any] {
            [kCGWindowBounds as String: rect.dictionaryRepresentation, kCGWindowLayer as String: layer,
             kCGWindowAlpha as String: 1, kCGWindowOwnerPID as String: pid]
        }
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let wechat = CGRect(x: 292, y: 121, width: 1135, height: 766)
        let calendar = CGRect(x: 740, y: 47, width: 960, height: 590)
        let background = CGRect(x: 0, y: 39, width: 1710, height: 1008)
        let dock = info(screen, layer: 20, pid: 100)
        for foreground in [info(wechat, layer: 0, pid: 200), info(calendar, layer: 3, pid: 300)] {
            for backdrop in [[], [info(background, layer: 0, pid: 400)]] {
                let candidates = ScreenshotWindowCandidate.frames(from: [dock, foreground] + backdrop,
                    primaryScreenHeight: screen.height, excludedOwnerPIDs: [100])
                let target = CGRect(dictionaryRepresentation: foreground[kCGWindowBounds as String] as! CFDictionary)!
                let expected = ScreenshotWindowCandidate.appKitRect(from: target, primaryScreenHeight: screen.height)
                XCTAssertEqual(candidates.first { $0.contains(CGPoint(x: expected.midX, y: expected.midY)) }, expected)
                XCTAssertEqual(candidates.count, 1 + backdrop.count)
            }
        }
        // 同层的第三方浮窗必须保留，不能以 layer == 20 作为排除条件。
        let appPanel = ScreenshotWindowCandidate.frames(from: [info(calendar, layer: 20, pid: 300)],
            primaryScreenHeight: screen.height, excludedOwnerPIDs: [100])
        XCTAssertEqual(appPanel.count, 1)
    }

    func testAppendPreservesEveryRowWithoutDuplicatingOverlap() throws {
        func frame(offset: Int) -> NSImage {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32)!
            for y in 0..<40 { for x in 0..<8 {
                let value = CGFloat(y + offset) / 100
                rep.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            } }
            let image = NSImage(size: CGSize(width: 8, height: 40)); image.addRepresentation(rep); return image
        }
        let output = LongScreenshotStitcher.append(frame(offset: 0), frame: frame(offset: 13), height: 13)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(output.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        XCTAssertEqual(bitmap.pixelsHigh, 53)
        for y in 0..<53 {
            let color = try XCTUnwrap(bitmap.colorAt(x: 4, y: y)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, CGFloat(y) / 100, accuracy: 0.015, "拼接第 \(y) 行错位")
        }
    }
}
