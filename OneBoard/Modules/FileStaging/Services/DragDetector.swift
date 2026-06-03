import AppKit

/// 全局鼠标拖拽 + 摇动手势检测器
final class DragDetector {
    static let shared = DragDetector()

    /// 摇动手势检测通知
    static let shakeGestureDetected = Notification.Name(Constants.NotificationNames.shakeGestureDetected)

    private var monitor: Any?
    private var localMonitor: Any?
    private var isDragging: Bool = false

    /// 最近鼠标位置记录（用于摇动检测）
    private var recentPositions: [(point: CGPoint, timestamp: TimeInterval)] = []

    private init() {}

    // MARK: - Start / Stop

    func start() {
        // 全局鼠标拖拽监控
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
        }

        // 本地事件监控（用于检测从 Finder 拖出的文件）
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event  // 本地监控必须返回 event
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    // MARK: - Event Handling

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            isDragging = true
            let position = NSEvent.mouseLocation
            let now = Date().timeIntervalSinceReferenceDate

            recentPositions.append((position, now))

            // 只保留最近 500ms 的数据
            recentPositions = recentPositions.filter {
                now - $0.timestamp < Constants.shakeWindowDuration
            }

            // 检测摇动手势
            if detectShake() {
                print("[DragDetector] 检测到摇动手势")
                NotificationCenter.default.post(
                    name: Self.shakeGestureDetected,
                    object: self
                )
                recentPositions.removeAll()
            }

        case .leftMouseUp:
            isDragging = false
            recentPositions.removeAll()

        default:
            break
        }
    }

    // MARK: - Shake Detection

    private func detectShake() -> Bool {
        guard recentPositions.count >= Constants.shakeMinPositions else { return false }

        var directionChanges = 0
        var lastDx: CGFloat = 0
        var initialized = false

        for i in 1..<recentPositions.count {
            let prev = recentPositions[i - 1]
            let curr = recentPositions[i]

            let dx = curr.point.x - prev.point.x
            let dy = curr.point.y - prev.point.y
            let dt = curr.timestamp - prev.timestamp

            // 移动速度需足够快（> 300 点/秒）
            let speed = sqrt(dx * dx + dy * dy) / max(CGFloat(dt), 0.001)
            guard speed > 300 else { continue }

            if initialized && ((lastDx > 0 && dx < 0) || (lastDx < 0 && dx > 0)) {
                directionChanges += 1
            }

            lastDx = dx
            initialized = true
        }

        return directionChanges >= Constants.shakeMinDirectionChanges
    }
}