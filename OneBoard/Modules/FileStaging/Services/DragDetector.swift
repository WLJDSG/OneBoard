import AppKit

/// 文件拖拽检测器 - 检测拖拽文件时的摇晃手势
final class DragDetector {
    static let shared = DragDetector()
    static let fileDragDetected = Notification.Name(Constants.NotificationNames.shakeGestureDetected)

    private var monitor: Any?
    private var localMonitor: Any?
    private var recentPositions: [(point: CGPoint, timestamp: TimeInterval)] = []
    private var lastTriggerTime: TimeInterval = 0

    private init() {}

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
        print("[DragDetector] 拖拽摇晃检测已启动")
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        recentPositions.removeAll()
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            guard isDraggingFile else {
                recentPositions.removeAll()
                return
            }

            let position = NSEvent.mouseLocation
            let now = Date().timeIntervalSinceReferenceDate
            recentPositions.append((position, now))
            recentPositions = recentPositions.filter { now - $0.timestamp < Constants.shakeWindowDuration }

            if detectShake(), now - lastTriggerTime > 1.2 {
                lastTriggerTime = now
                recentPositions.removeAll()
                print("[DragDetector] 检测到文件拖拽摇晃手势")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.fileDragDetected, object: self)
                }
            }

        case .leftMouseUp:
            recentPositions.removeAll()

        default:
            break
        }
    }

    private var isDraggingFile: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let types = pasteboard.types ?? []
        return types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            || types.contains { $0.rawValue.localizedCaseInsensitiveContains("file-url") }
    }

    private func detectShake() -> Bool {
        guard recentPositions.count >= Constants.shakeMinPositions else { return false }

        var directionChanges = 0
        var previousDirection: CGFloat = 0

        for index in 1..<recentPositions.count {
            let previous = recentPositions[index - 1]
            let current = recentPositions[index]
            let dx = current.point.x - previous.point.x
            let dy = current.point.y - previous.point.y
            let dt = current.timestamp - previous.timestamp
            let speed = hypot(dx, dy) / max(CGFloat(dt), 0.001)

            guard speed > 300, abs(dx) > 8 else { continue }

            let direction: CGFloat = dx > 0 ? 1 : -1
            if previousDirection != 0, direction != previousDirection {
                directionChanges += 1
            }
            previousDirection = direction
        }

        return directionChanges >= Constants.shakeMinDirectionChanges
    }
}
