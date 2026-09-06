import AppKit
import SwiftUI

enum SettingsReorder {
    static func moving(_ source: UUID, relativeTo target: UUID, after: Bool, in ids: [UUID]) -> [UUID] {
        guard source != target, ids.contains(source), ids.contains(target) else { return ids }
        var result = ids.filter { $0 != source }
        let index = result.firstIndex(of: target)!
        result.insert(source, at: index + (after ? 1 : 0))
        return result
    }
}

/// 只在投放成功时持久化。原生拖拽会话结束回调覆盖 Esc、窗口外松手和取消。
struct SettingsReorderList<Item: Identifiable, Content: View>: View where Item.ID == UUID {
    let items: [Item]
    let title: (Item) -> String
    let onCommit: ([UUID]) -> Void
    @ViewBuilder let content: (Item) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedID: UUID?
    @State private var previewIDs: [UUID] = []

    private var ordered: [Item] {
        guard draggedID != nil else { return items }
        return previewIDs.compactMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(ordered) { item in
                HStack(alignment: .top, spacing: 8) {
                    SettingsReorderHandle(title: title(item), id: item.id, onBegin: {
                        previewIDs = items.map(\.id)
                        draggedID = item.id
                    }, onEnd: { draggedID = nil; previewIDs = [] })
                    .frame(width: 24, height: 38)
                    .help("拖拽调整顺序，也可右键上移或下移")
                    .contextMenu {
                        Button("上移") { step(item.id, direction: -1) }.disabled(items.first?.id == item.id)
                        Button("下移") { step(item.id, direction: 1) }.disabled(items.last?.id == item.id)
                    }
                    content(item)
                }
                .opacity(draggedID == item.id ? 0.08 : 1)
                .overlay {
                    if draggedID == item.id {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(SettingsPalette.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .background(SettingsPalette.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(Text("放在这里").font(.callout).foregroundStyle(SettingsPalette.accent))
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [SettingsReorderHandle.pasteboardType.rawValue], delegate: SettingsReorderDrop(
                    target: item.id, draggedID: $draggedID, previewIDs: $previewIDs,
                    animate: !reduceMotion, onCommit: onCommit))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: previewIDs)
        .onChange(of: items.map(\.id)) { _, _ in draggedID = nil; previewIDs = [] }
        .onDisappear { draggedID = nil; previewIDs = [] }
    }

    private func step(_ id: UUID, direction: Int) {
        let ids = items.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + direction) else { return }
        onCommit(SettingsReorder.moving(id, relativeTo: ids[index + direction], after: direction > 0, in: ids))
    }
}

private struct SettingsReorderDrop: DropDelegate {
    let target: UUID
    @Binding var draggedID: UUID?
    @Binding var previewIDs: [UUID]
    let animate: Bool
    let onCommit: ([UUID]) -> Void

    func validateDrop(info: DropInfo) -> Bool { draggedID != nil }
    func dropEntered(info: DropInfo) {
        guard let source = draggedID, let from = previewIDs.firstIndex(of: source),
              let to = previewIDs.firstIndex(of: target), source != target else { return }
        let updated = SettingsReorder.moving(source, relativeTo: target, after: from < to, in: previewIDs)
        withAnimation(animate ? .spring(response: 0.28, dampingFraction: 0.86) : nil) { previewIDs = updated }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard draggedID != nil else { return false }
        onCommit(previewIDs)
        draggedID = nil
        previewIDs = []
        return true
    }
}

private struct SettingsReorderHandle: NSViewRepresentable {
    static let pasteboardType = NSPasteboard.PasteboardType.string
    let title: String
    let id: UUID
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.title = title; view.itemID = id; view.onBegin = onBegin; view.onEnd = onEnd
        view.setAccessibilityLabel("拖拽排序：" + title)
    }

    final class HandleView: NSView, NSDraggingSource {
        var title = ""
        var itemID = UUID()
        var onBegin: () -> Void = {}
        var onEnd: () -> Void = {}
        private var dragging = false
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func draw(_ dirtyRect: NSRect) {
            NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
                .draw(in: NSRect(x: 4, y: 12, width: 16, height: 14))
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDragged(with event: NSEvent) {
            guard !dragging else { return }
            dragging = true
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(itemID.uuidString, forType: SettingsReorderHandle.pasteboardType)
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let image = NSImage(size: NSSize(width: 240, height: 42), flipped: false) { rect in
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
                (self.title as NSString).draw(in: rect.insetBy(dx: 14, dy: 12), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
                ])
                return true
            }
            item.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: image.size), contents: image)
            onBegin()
            beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragging = false
            onEnd()
        }
    }
}
