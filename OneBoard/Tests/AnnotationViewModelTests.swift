import AppKit
@testable import OneBoardKit
import XCTest

@MainActor
final class AnnotationViewModelTests: XCTestCase {
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
