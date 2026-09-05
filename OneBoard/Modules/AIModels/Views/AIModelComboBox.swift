import SwiftUI
import AppKit

/// 模型目录可选、模型 ID 可输入，兼容未提供目录的供应商。
struct AIModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let models: [String]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.isEditable = true
        combo.completes = true
        combo.numberOfVisibleItems = 12
        combo.placeholderString = "选择或输入模型 ID"
        combo.delegate = context.coordinator
        combo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return combo
    }

    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.models != models {
            context.coordinator.models = models
            combo.removeAllItems()
            combo.addItems(withObjectValues: models)
        }
        if combo.stringValue != text { combo.stringValue = text }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: AIModelComboBox
        var models: [String] = []

        init(_ parent: AIModelComboBox) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox,
                  let value = combo.objectValueOfSelectedItem as? String else { return }
            parent.text = value
        }
    }
}
