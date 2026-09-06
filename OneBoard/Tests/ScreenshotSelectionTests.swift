import AppKit
import SwiftUI
@testable import OneBoardKit
import XCTest

final class ScreenshotSelectionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)

    @MainActor
    func testToolbarMouseDoesNotRestartSelectionAndTranslationFinishesOnce() throws {
        let view = ScreenshotOverlayContentView(screenshot: try makeRasterImage(size: bounds.size), eventManager: OverlayEventManager())
        view.frame = bounds
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 100, y: 150)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 500, y: 400)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 500, y: 400)))
        let original = try selectionModel(from: view).rect
        let toolbar = try XCTUnwrap(view.subviews.compactMap { $0 as? NSHostingView<AnnotationToolbarView> }.first)
        let point = CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY)
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: point))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: point))
        XCTAssertEqual(try selectionModel(from: view).rect, original)
        XCTAssertFalse(toolbar.isHidden)
        var actions: [ScreenshotSelectionAction] = []
        view.onConfirm = { image, _, action in
            XCTAssertEqual(image.size, original?.size)
            actions.append(action)
        }
        toolbar.rootView.handleTranslationOutput(toolbar.rootView.baseImage)
        toolbar.rootView.handleTranslationOutput(toolbar.rootView.baseImage)
        XCTAssertEqual(actions, [.translate])
    }

    func testMovingSelectionClampsToScreenBounds() {
        let result = ScreenshotSelectionGeometry.moved(
            CGRect(x: 800, y: 500, width: 180, height: 160),
            by: CGSize(width: 100, height: 100),
            inside: bounds
        )

        XCTAssertEqual(result, CGRect(x: 820, y: 540, width: 180, height: 160))
    }

    func testTopLeftResizeMovesOnlyTopAndLeftEdges() {
        let result = ScreenshotSelectionGeometry.resized(
            CGRect(x: 200, y: 200, width: 300, height: 200),
            handle: .topLeft,
            to: CGPoint(x: 150, y: 460),
            inside: bounds,
            minimumSize: CGSize(width: 24, height: 24)
        )

        XCTAssertEqual(result, CGRect(x: 150, y: 200, width: 350, height: 260))
    }

    func testAllResizeHandlesChangeExpectedEdges() {
        let rect = CGRect(x: 200, y: 200, width: 300, height: 200)
        let cases: [(ScreenshotResizeHandle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 150, y: 450), CGRect(x: 150, y: 200, width: 350, height: 250)),
            (.top, CGPoint(x: 350, y: 450), CGRect(x: 200, y: 200, width: 300, height: 250)),
            (.topRight, CGPoint(x: 550, y: 450), CGRect(x: 200, y: 200, width: 350, height: 250)),
            (.right, CGPoint(x: 550, y: 300), CGRect(x: 200, y: 200, width: 350, height: 200)),
            (.bottomRight, CGPoint(x: 550, y: 150), CGRect(x: 200, y: 150, width: 350, height: 250)),
            (.bottom, CGPoint(x: 350, y: 150), CGRect(x: 200, y: 150, width: 300, height: 250)),
            (.bottomLeft, CGPoint(x: 150, y: 150), CGRect(x: 150, y: 150, width: 350, height: 250)),
            (.left, CGPoint(x: 150, y: 300), CGRect(x: 150, y: 200, width: 350, height: 200)),
        ]

        for (handle, point, expected) in cases {
            XCTAssertEqual(
                ScreenshotSelectionGeometry.resized(
                    rect,
                    handle: handle,
                    to: point,
                    inside: bounds,
                    minimumSize: CGSize(width: 24, height: 24)
                ),
                expected,
                "Unexpected geometry for \(handle)"
            )
        }
    }

    func testResizeHonorsMinimumSize() {
        let result = ScreenshotSelectionGeometry.resized(
            CGRect(x: 200, y: 200, width: 300, height: 200),
            handle: .bottomLeft,
            to: CGPoint(x: 490, y: 390),
            inside: bounds,
            minimumSize: CGSize(width: 24, height: 24)
        )

        XCTAssertEqual(result, CGRect(x: 476, y: 376, width: 24, height: 24))
    }

    func testClickOutsideExistingSelectionStartsNewSelection() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))

        model.begin(at: CGPoint(x: 700, y: 500), bounds: bounds)
        model.update(to: CGPoint(x: 850, y: 620), bounds: bounds)
        model.end(at: CGPoint(x: 850, y: 620), bounds: bounds)

        XCTAssertEqual(model.rect, CGRect(x: 700, y: 500, width: 150, height: 120))
        XCTAssertEqual(model.phase, .adjusting)
    }

    func testDraggingInsideSelectionMovesIt() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))

        model.begin(at: CGPoint(x: 150, y: 150), bounds: bounds)
        model.update(to: CGPoint(x: 250, y: 225), bounds: bounds)
        model.end(at: CGPoint(x: 250, y: 225), bounds: bounds)

        XCTAssertEqual(model.rect, CGRect(x: 200, y: 175, width: 200, height: 150))
    }

    func testLockReturnsSelectionOnlyOnceAndPreventsChanges() {
        var model = ScreenshotSelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 150))

        XCTAssertEqual(model.lock(), model.rect)
        XCTAssertNil(model.lock())
        model.begin(at: CGPoint(x: 150, y: 150), bounds: bounds)
        model.update(to: CGPoint(x: 400, y: 400), bounds: bounds)
        model.end(at: CGPoint(x: 400, y: 400), bounds: bounds)

        XCTAssertEqual(model.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(model.phase, .locked)
    }

    func testOverlayKeepsSelectionAdjustableAfterMouseUp() throws {
        let view = ScreenshotOverlayContentView(
            screenshot: NSImage(size: bounds.size),
            eventManager: OverlayEventManager()
        )
        view.frame = bounds

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 400, y: 300)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 400, y: 300)))

        let model = try XCTUnwrap(
            Mirror(reflecting: view).children.first(where: { $0.label == "selectionModel" })?.value
                as? ScreenshotSelectionModel
        )
        XCTAssertEqual(model.phase, .adjusting)
    }

    @MainActor
    func testSelectingAnnotationToolImmediatelyLocksSelectionAndInstallsCanvas() throws {
        let image = try makeRasterImage(size: bounds.size)
        let view = ScreenshotOverlayContentView(
            screenshot: image,
            eventManager: OverlayEventManager()
        )
        view.frame = bounds
        let window = NSWindow(
            contentRect: bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        defer { window.close() }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 400, y: 300)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 400, y: 300)))

        XCTAssertTrue(view.canCropSelectionForTesting)
        let service = try XCTUnwrap(view.annotationServiceForTesting)
        view.handleAnnotationToolSelection(.rectangle)

        let model = try selectionModel(from: view)
        XCTAssertEqual(service.selectedTool, .rectangle)
        XCTAssertEqual(model.phase, .locked, "选择标注工具后应立即锁定选区")
        XCTAssertTrue(view.hasAnnotationCanvasForTesting, "选择标注工具后应立即安装标注画布")
    }

    @MainActor
    func testWindowPreviewRetainsOpaqueScreenshotPixels() throws {
        let rect = CGRect(x: 200, y: 200, width: 300, height: 200)
        let image = try makeRasterImage(size: bounds.size)
        let source = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        for y in 430..<470 {
            for x in 230..<270 {
                source.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        let screenshot = NSImage(size: bounds.size)
        screenshot.addRepresentation(source)
        let view = ScreenshotOverlayContentView(screenshot: screenshot, eventManager: OverlayEventManager(), windowCandidates: [rect])
        view.frame = bounds
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 250, y: 250)))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let x = Int(250 * CGFloat(bitmap.pixelsWide) / bounds.width)
        let y = Int((bounds.height - 250) * CGFloat(bitmap.pixelsHigh) / bounds.height)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 1, accuracy: 0.01,
                       "预选区必须保留截图背景，不得挖出鼠标可穿透的透明洞")
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        // 离屏位图会经过显示器颜色配置转换，用红色区域位置验证方向而不假定设备 RGB 数值不变。
        XCTAssertGreaterThan(color.redComponent, 0.8)
        XCTAssertLessThan(color.greenComponent, 0.25, "冻结背景应保持原图方向与内容")
        XCTAssertLessThan(color.blueComponent, 0.25)
        if let directory = ProcessInfo.processInfo.environment["ONEBOARD_RENDER_DIRECTORY"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("window-hover.png"))
        }
    }

    @MainActor
    func testWindowPreviewSurvivesMouseDownAndSmallJitter() throws {
        let rect = CGRect(x: 200, y: 200, width: 300, height: 200)
        let view = ScreenshotOverlayContentView(screenshot: try makeRasterImage(size: bounds.size), eventManager: OverlayEventManager(), windowCandidates: [rect])
        view.frame = bounds
        let point = CGPoint(x: 250, y: 250)
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: point))
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: point))
        XCTAssertNil(try selectionModel(from: view).rect, "超过拖动阈值前不能创建零尺寸选区")
        XCTAssertEqual(Mirror(reflecting: view).children.first { $0.label == "hoveredWindowRect" }?.value as? CGRect, rect)
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 252, y: 251)))
        XCTAssertNil(try selectionModel(from: view).rect)
        XCTAssertEqual(Mirror(reflecting: view).children.first { $0.label == "hoveredWindowRect" }?.value as? CGRect, rect)
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 252, y: 251)))
        XCTAssertEqual(try selectionModel(from: view).rect, rect)
    }

    @MainActor
    func testWindowHoverClickAndCustomDrag() throws {
        let front = CGRect(x: 200, y: 200, width: 300, height: 200)
        let back = CGRect(x: 100, y: 100, width: 700, height: 500)
        let view = ScreenshotOverlayContentView(screenshot: try makeRasterImage(size: bounds.size), eventManager: OverlayEventManager(), windowCandidates: [front, back])
        view.frame = bounds
        let point = CGPoint(x: 250, y: 250)
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, location: point))
        let hover = Mirror(reflecting: view).children.first { $0.label == "hoveredWindowRect" }?.value as? CGRect
        XCTAssertEqual(hover, front)
        XCTAssertNil(try selectionModel(from: view).rect, "悬停不能直接提交选区")
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: point))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: point))
        XCTAssertEqual(try selectionModel(from: view).rect, front)
        XCTAssertEqual(try selectionModel(from: view).phase, .adjusting)

        let custom = ScreenshotOverlayContentView(screenshot: try makeRasterImage(size: bounds.size), eventManager: OverlayEventManager(), windowCandidates: [front, back])
        custom.frame = bounds
        custom.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: point))
        custom.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, location: CGPoint(x: 450, y: 350)))
        custom.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: CGPoint(x: 450, y: 350)))
        XCTAssertEqual(try selectionModel(from: custom).rect, CGRect(x: 250, y: 250, width: 200, height: 100))
    }

    func testWindowCoordinatesAcrossDisplays() {
        let quartz = CGRect(x: -400, y: -200, width: 600, height: 400)
        let frame = ScreenshotWindowCandidate.appKitRect(from: quartz, primaryScreenHeight: 900)
        XCTAssertEqual(frame, CGRect(x: -400, y: 700, width: 600, height: 400))
        XCTAssertEqual(ScreenshotWindowCandidate.localRects([frame], screenFrame: CGRect(x: -1000, y: 0, width: 1000, height: 1000)),
                       [CGRect(x: 600, y: 700, width: 400, height: 300)])
        XCTAssertEqual(ScreenshotWindowCandidate.localRects([frame], screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                       [CGRect(x: 0, y: 700, width: 200, height: 200)])
    }

    private func selectionModel(from view: ScreenshotOverlayContentView) throws -> ScreenshotSelectionModel {
        try XCTUnwrap(
            Mirror(reflecting: view).children.first(where: { $0.label == "selectionModel" })?.value
                as? ScreenshotSelectionModel
        )
    }

    private func makeRasterImage(size: CGSize) throws -> NSImage {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        return try XCTUnwrap(NSImage(data: png))
    }

    private func mouseEvent(type: NSEvent.EventType, location: CGPoint) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

}
