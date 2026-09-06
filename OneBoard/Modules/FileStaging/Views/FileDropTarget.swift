import AppKit
import SwiftUI

/// 使用 Finder 原生拖放协议，在非激活刘海面板里直接接收文件 URL。
struct FileDropTarget: NSViewRepresentable {
    @Binding var targeted: Bool
    var receive: ([URL]) -> Void
    func makeNSView(context: Context) -> Destination {
        let view = Destination()
        view.registerForDraggedTypes([.fileURL, .init("NSFilenamesPboardType")])
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
            let native = (pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) ?? []).compactMap { object -> URL? in
                guard let url = object as? NSURL else { return nil }
                return url as URL
            }
            if !native.isEmpty { return native }

            let itemURLs = urls(from: pasteboard.pasteboardItems ?? [])
            if !itemURLs.isEmpty { return itemURLs }

            if let value = pasteboard.string(forType: .fileURL), let url = URL(string: value) {
                return [url]
            }

            let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            return urls(fromLegacyPropertyList: pasteboard.propertyList(forType: legacyType))
        }

        static func urls(from items: [NSPasteboardItem]) -> [URL] {
            items.compactMap { item -> URL? in
                guard let value = item.string(forType: .fileURL) else { return nil }
                return URL(string: value)
            }
        }

        static func urls(fromLegacyPropertyList value: Any?) -> [URL] {
            let paths = value as? [String] ?? []
            return paths.map(URL.init(fileURLWithPath:))
        }
    }
}
