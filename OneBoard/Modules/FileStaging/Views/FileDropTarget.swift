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
            // 旧载荷仅提供路径；避免 URL 初始化时自动探测目录属性。
            return paths.map { URL(fileURLWithPath: $0, isDirectory: false) }
        }
    }
}

/// SwiftUI 会把透明 Representable 的命中收回到 HostingView；显式转交原生拖放区域。
final class FileShelfHostingView<Content: View>: NSHostingView<Content> {
    private weak var activeDestination: FileDropTarget.Destination?
    private let fallbackDestination = FileDropTarget.Destination()
    var receiveFiles: (([URL]) -> Void)? {
        didSet { fallbackDestination.receive = { [weak self] in self?.receiveFiles?($0) } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, .init("NSFilenamesPboardType")])
    }

    private func destination(at windowPoint: CGPoint) -> FileDropTarget.Destination? {
        func find(in view: NSView) -> FileDropTarget.Destination? {
            guard !view.isHidden else { return nil }
            if let destination = view as? FileDropTarget.Destination,
               view.bounds.contains(view.convert(windowPoint, from: nil)) { return destination }
            return view.subviews.reversed().lazy.compactMap { find(in: $0) }.first
        }
        return find(in: self) ?? (receiveFiles == nil ? nil : fallbackDestination)
    }

    // NSHostingView 自己实现了拖放回调，只转交 hitTest 不会进入原生 Destination。
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let next = destination(at: sender.draggingLocation)
        if activeDestination !== next { activeDestination?.draggingExited(sender) }
        activeDestination = next
        return next?.draggingEntered(sender) ?? []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        activeDestination?.draggingExited(sender)
        activeDestination = nil
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        destination(at: sender.draggingLocation)?.prepareForDragOperation(sender) ?? false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { draggingExited(sender) }
        return destination(at: sender.draggingLocation)?.performDragOperation(sender) ?? false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        func receiver(in view: NSView) -> NSView? {
            guard !view.isHidden else { return nil }
            if view is FileDropTarget.Destination || view is FileDragSource.Source {
                let local = view.convert(point, from: superview ?? self)
                return view.bounds.contains(local) ? view : nil
            }
            return view.subviews.reversed().lazy.compactMap { receiver(in: $0) }.first
        }
        return receiver(in: self) ?? hit
    }
}

/// 拖出写入 NSURL，由 Finder 决定复制目标，不能把文件内容或文本路径当成文件拖拽。
struct FileDragSource: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> Source { Source() }
    func updateNSView(_ view: Source, context: Context) { view.url = url }

    final class Source: NSView, NSDraggingSource {
        var url: URL?
        private var startEvent: NSEvent?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { startEvent = event }
        override func mouseUp(with event: NSEvent) { startEvent = nil }
        override func mouseDragged(with event: NSEvent) {
            guard let start = startEvent, let url,
                  !DragDetector.supportedDraggedFileURLs([url]).isEmpty else { return }
            guard hypot(event.locationInWindow.x - start.locationInWindow.x,
                        event.locationInWindow.y - start.locationInWindow.y) >= 3 else { return }
            startEvent = nil
            let point = convert(event.locationInWindow, from: nil)
            beginDraggingSession(with: [Self.draggingItem(url: url, at: point)], event: event, source: self)
        }
        static func draggingItem(url: URL, at point: CGPoint) -> NSDraggingItem {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }
}
