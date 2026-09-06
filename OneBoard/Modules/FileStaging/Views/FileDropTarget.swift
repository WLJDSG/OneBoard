import AppKit
import SwiftUI

/// 使用 Finder 原生拖放协议，在非激活刘海面板里直接接收文件 URL。
struct FileDropTarget: NSViewRepresentable {
    @Binding var targeted: Bool
    var receive: ([URL]) -> Void
    func makeNSView(context: Context) -> Destination {
        let view = Destination()
        view.registerForDraggedTypes([.fileURL])
        return view
    }
    func updateNSView(_ view: Destination, context: Context) {
        view.receive = receive
        view.targetChanged = { targeted = $0 }
    }
    final class Destination: NSView {
        var receive: ([URL]) -> Void = { _ in }
        var targetChanged: (Bool) -> Void = { _ in }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let accepts = !Self.urls(sender.draggingPasteboard).isEmpty
            targetChanged(accepts)
            return accepts ? .copy : []
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
        override func draggingExited(_ sender: NSDraggingInfo?) { targetChanged(false) }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !Self.urls(sender.draggingPasteboard).isEmpty }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            targetChanged(false)
            let urls = Self.urls(sender.draggingPasteboard)
            guard !urls.isEmpty else { return false }
            receive(urls)
            return true
        }
        static func urls(_ pasteboard: NSPasteboard) -> [URL] {
            (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        }
    }
}
