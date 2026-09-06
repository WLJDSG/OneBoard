import AppKit

/// 轮询当前文件拖拽会话，不监听系统输入事件。
final class DragDetector {
    static let shared = DragDetector()
    static let fileDragDetected = Notification.Name(Constants.NotificationNames.shakeGestureDetected)

    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var isDragConfirmed: Bool = false  // 当前拖拽已确认是文件拖拽
    private var didNotifyCurrentDrag = false

    private var idlePasteboardChangeCount: Int
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.pasteboard = pasteboard
        self.idlePasteboardChangeCount = pasteboard.changeCount
    }

    func start() {
        guard pollTimer == nil else { return }
        finishCurrentDrag()
        startPolling()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
        print("[DragDetector] 已启动")
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        finishCurrentDrag()
    }

    // MARK: - 轮询

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isLeftMouseButtonDown else {
                self.finishCurrentDrag()
                return
            }
            guard self.isDraggingSupportedContent else {
                return
            }
            self.handleDrag()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            guard isDraggingSupportedContent else {
                break
            }
            handleDrag()
        case .leftMouseDown, .leftMouseUp:
            finishCurrentDrag()
        default: break
        }
    }

    private func handleDrag() {
        guard isFileDragActive, shouldRevealShelfForCurrentDrag() else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.fileDragDetected, object: self)
        }
    }

    func shouldRevealShelfForCurrentDrag() -> Bool {
        guard isDraggingSupportedContent, !didNotifyCurrentDrag else { return false }
        didNotifyCurrentDrag = true
        return true
    }

    // MARK: - 拖拽内容检测

    /// 松手立即失效，不把 .drag 上一次留下的文件误认为仍在拖动。
    var isFileDragActive: Bool {
        guard isLeftMouseButtonDown else {
            finishCurrentDrag()
            return false
        }
        return isDraggingSupportedContent
    }

    var isDraggingSupportedContent: Bool {
        // 已确认的拖拽直接返回 true（同一拖拽操作中 changeCount 不变，避免后续帧误判）
        if isDragConfirmed { return true }

        // .drag 松手后保留上次文件，必须有本次按下期间的新写入才能确认。
        return updateDragState(
            changeCount: pasteboard.changeCount,
            types: pasteboard.types ?? [],
            urls: FileDropTarget.Destination.urls(pasteboard)
        )
    }

    func updateDragState(
        changeCount: Int,
        types: [NSPasteboard.PasteboardType],
        urls: [URL]
    ) -> Bool {
        if isDragConfirmed { return true }
        guard changeCount != idlePasteboardChangeCount,
              Self.canConfirmFileDrag(types: types, urls: urls) else { return false }
        isDragConfirmed = true
        return true
    }

    static func supportsDraggedFileTypes(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        let fileTypes: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            "public.file-url",
            "NSFilenamesPboardType"
        ]
        return types.contains { fileTypes.contains($0.rawValue) }
    }

    static func canConfirmFileDrag(
        types: [NSPasteboard.PasteboardType],
        urls: [URL]
    ) -> Bool {
        supportsDraggedFileTypes(types) && !supportedDraggedFileURLs(urls).isEmpty
    }

    static func supportedDraggedFileURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard url.isFileURL,
                  url.pathExtension.lowercased() != "app",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
                return false
            }
            return values.isRegularFile == true
        }
    }

    // MARK: - 工具方法

    private var isLeftMouseButtonDown: Bool {
        (NSEvent.pressedMouseButtons & 1) == 1
    }

    func finishCurrentDrag() {
        isDragConfirmed = false
        didNotifyCurrentDrag = false
        idlePasteboardChangeCount = pasteboard.changeCount
    }

}
