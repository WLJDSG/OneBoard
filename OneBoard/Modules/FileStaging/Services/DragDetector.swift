import AppKit

/// 文件拖拽检测器 - 检测拖拽内容时的摇晃手势
final class DragDetector {
    static let shared = DragDetector()
    static let fileDragDetected = Notification.Name(Constants.NotificationNames.shakeGestureDetected)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var recentPositions: [(point: CGPoint, timestamp: TimeInterval)] = []
    private var lastTriggerTime: TimeInterval = 0

    private init() {}

    func start() {
        startEventTap()
        startPolling()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
        print("[DragDetector] 拖拽摇晃检测已启动")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        recentPositions.removeAll()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let position = NSEvent.mouseLocation
            if self.isDraggingSupportedContent || self.isLeftMouseButtonDown || !self.recentPositions.isEmpty {
                self.handleDrag(at: position)
            }
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func startEventTap() {
        let mask = (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<DragDetector>.fromOpaque(userInfo).takeUnretainedValue()
                detector.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            print("[DragDetector] CGEventTap 创建失败，可能缺少辅助功能权限")
            print("[DragDetector] 将使用轮询模式兜底检测拖拽摇晃")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDragged:
            handleDrag(at: event.location)
        case .leftMouseUp:
            recentPositions.removeAll()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            handleDrag(at: NSEvent.mouseLocation)
        case .leftMouseUp:
            recentPositions.removeAll()
        default:
            break
        }
    }

    private func handleDrag(at position: CGPoint) {
        let inTopZone = isInTopTriggerZone(position)
        guard isDraggingSupportedContent || inTopZone || isLeftMouseButtonDown || !recentPositions.isEmpty else {
            recentPositions.removeAll()
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        recentPositions.append((position, now))
        recentPositions = recentPositions.filter { now - $0.timestamp < Constants.shakeWindowDuration }

        if (detectShake() || inTopZone), now - lastTriggerTime > 1.0 {
            lastTriggerTime = now
            recentPositions.removeAll()
            print("[DragDetector] 检测到拖拽摇晃手势")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.fileDragDetected, object: self)
            }
        }
    }

    private var isDraggingSupportedContent: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let types = pasteboard.types ?? []
        if types.isEmpty { return false }

        let supportedNames = [
            "public.file-url",
            "NSFilenamesPboardType",
            "public.url",
            "public.utf8-plain-text",
            "public.tiff",
            "public.png"
        ]

        return types.contains { type in
            supportedNames.contains(type.rawValue)
                || type.rawValue.localizedCaseInsensitiveContains("file")
                || type.rawValue.localizedCaseInsensitiveContains("url")
        }
    }

    private var isLeftMouseButtonDown: Bool {
        (NSEvent.pressedMouseButtons & 1) == 1
    }

    private func detectShake() -> Bool {
        guard recentPositions.count >= 4 else { return false }

        var directionChanges = 0
        var previousDirection: CGFloat = 0

        for index in 1..<recentPositions.count {
            let previous = recentPositions[index - 1]
            let current = recentPositions[index]
            let dx = current.point.x - previous.point.x
            let dy = current.point.y - previous.point.y
            let dt = current.timestamp - previous.timestamp
            let speed = hypot(dx, dy) / max(CGFloat(dt), 0.001)

            guard speed > 160, abs(dx) > 5, abs(dx) > abs(dy) * 0.7 else { continue }

            let direction: CGFloat = dx > 0 ? 1 : -1
            if previousDirection != 0, direction != previousDirection {
                directionChanges += 1
            }
            previousDirection = direction
        }

        return directionChanges >= 2
    }

    private func isInTopTriggerZone(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return false
        }
        let frame = screen.frame
        let zoneWidth: CGFloat = 180
        let zoneHeight: CGFloat = 44
        let zone = CGRect(
            x: frame.midX - zoneWidth / 2,
            y: frame.maxY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )
        return zone.contains(point)
    }
}
