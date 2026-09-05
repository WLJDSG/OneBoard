import AppKit
import XCTest
@testable import OneBoardKit

@MainActor
final class AIModelComboBoxTests: XCTestCase {
    func testSelectingCatalogModelUpdatesBinding() {
        var selected = "old-model"
        let field = AIModelComboBox(
            text: .init(get: { selected }, set: { selected = $0 }),
            models: ["model-a", "model-b"]
        )
        let coordinator = field.makeCoordinator()
        let combo = NSComboBox()
        combo.addItems(withObjectValues: field.models)
        combo.selectItem(at: 1)
        coordinator.comboBoxSelectionDidChange(Notification(name: NSComboBox.selectionDidChangeNotification, object: combo))
        XCTAssertEqual(selected, "model-b")
    }

    func testManualModelEntryWorksWithoutCatalog() {
        var selected = ""
        let field = AIModelComboBox(text: .init(get: { selected }, set: { selected = $0 }), models: [])
        let combo = NSComboBox()
        combo.stringValue = "custom-model"
        field.makeCoordinator().controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: combo))
        XCTAssertEqual(selected, "custom-model")
    }
}
