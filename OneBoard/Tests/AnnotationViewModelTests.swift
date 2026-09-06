import AppKit
import SwiftUI
@testable import OneBoardKit
import XCTest

@MainActor
final class AnnotationViewModelTests: XCTestCase {
    func testDoubleClickReusesInlineEditorAndEditsCanUndoOrCancel() throws {
        let service = AnnotationService()
        service.addText(in: CGRect(x: 20, y: 30, width: 160, height: 40), text: "原文字", fontSize: 16)
        let model = AnnotationViewModel(annotationService: service)
        let id = try XCTUnwrap(service.layers.first?.id)
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 60, y: 50),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        model.beginInteraction(at: CGPoint(x: 60, y: 50), event: click)
        XCTAssertEqual(model.selectedTextLayerID, id)
        XCTAssertFalse(model.isTextInput)
        XCTAssertEqual(service.fontSize, 16)
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 60, y: 50),
            modifierFlags: [], timestamp: 0.1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        model.beginInteraction(at: CGPoint(x: 60, y: 50), event: doubleClick)
        XCTAssertTrue(model.isTextInput)
        XCTAssertEqual(model.initialTextValue, "原文字")
        XCTAssertEqual(model.textInputRect, service.layers[0].rect)
        model.textInputRect.origin.x = 50
        model.commitText("新文字")
        XCTAssertEqual(service.layers.count, 1)
        XCTAssertEqual(service.layers[0].text, "新文字")
        XCTAssertEqual(service.layers[0].rect.origin.x, 50)
        service.undo()
        XCTAssertEqual(service.layers[0].text, "原文字")
        XCTAssertEqual(service.layers[0].rect.origin.x, 20)
        model.selectedTextLayerID = id
        model.enterTextEdit()
        model.textInputRect.origin.x = 90
        model.cancelTextInput()
        XCTAssertFalse(model.isTextInput)
        XCTAssertNil(model.editingTextLayerID)
        XCTAssertEqual(service.layers[0].rect.origin.x, 20)
    }

    func testStyleControlLabelsDescribeAllToolSizes() {
        XCTAssertEqual(AnnotationToolbarView.styleLabel(for: .text), "字号")
        XCTAssertEqual(AnnotationToolbarView.styleLabel(for: .arrow), "线宽")
        XCTAssertEqual(AnnotationToolbarView.styleLabel(for: .mosaic), "颗粒")
        XCTAssertEqual(AnnotationToolbarView.styleLabel(for: .number), "编号")
    }

    func testSwiftUIHostingViewUsesFlippedCoordinates() {
        let hostingView = NSHostingView(rootView: EmptyView())

        XCTAssertTrue(hostingView.isFlipped)
    }

    func testFlippedHostingViewKeepsMouseMovementDirection() {
        let start = AnnotationCoordinateMapper.imagePoint(
            from: CGPoint(x: 30, y: 40),
            boundsHeight: 300,
            isFlipped: true
        )
        let end = AnnotationCoordinateMapper.imagePoint(
            from: CGPoint(x: 90, y: 120),
            boundsHeight: 300,
            isFlipped: true
        )

        XCTAssertEqual(end.x - start.x, 60)
        XCTAssertEqual(end.y - start.y, 80)
    }

    func testNonFlippedAppKitViewConvertsToTopLeftCoordinatesOnce() {
        let point = AnnotationCoordinateMapper.imagePoint(
            from: CGPoint(x: 30, y: 40),
            boundsHeight: 300,
            isFlipped: false
        )

        XCTAssertEqual(point, CGPoint(x: 30, y: 260))
    }

    func testSelectToolForNumberKeyMapsAnsiNumberRowKeys() {
        let service = AnnotationService()
        let viewModel = AnnotationViewModel(annotationService: service)

        let cases: [(UInt16, AnnotationTool)] = [
            (18, .cursor),
            (19, .rectangle),
            (20, .ellipse),
            (21, .arrow),
            (23, .line),
            (22, .text),
            (26, .number),
            (28, .mosaic),
        ]

        for (keyCode, expectedTool) in cases {
            XCTAssertTrue(viewModel.selectTool(forNumberKey: keyCode))
            XCTAssertEqual(service.selectedTool, expectedTool)
        }
    }

    func testSelectToolForUnknownNumberKeyDoesNotChangeCurrentTool() {
        let service = AnnotationService()
        service.selectedTool = .rectangle
        let viewModel = AnnotationViewModel(annotationService: service)

        XCTAssertFalse(viewModel.selectTool(forNumberKey: 99))
        XCTAssertEqual(service.selectedTool, .rectangle)
    }

    func testRedoRestoresLayerAfterUndo() {
        let service = AnnotationService()
        let viewModel = AnnotationViewModel(annotationService: service)
        service.addRectangle(CGRect(x: 1, y: 2, width: 30, height: 40))
        service.addNumber(at: CGPoint(x: 60, y: 60))

        viewModel.undo()
        XCTAssertEqual(service.layers.count, 1)

        viewModel.redo()

        XCTAssertEqual(service.layers.count, 2)
        XCTAssertEqual(service.layers.last?.tool, .number)
        XCTAssertEqual(service.layers.last?.numberValue, 1)
    }
}
