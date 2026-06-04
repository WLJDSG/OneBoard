import AppKit

/// 文件拖拽检测器 - 检测拖拽内容时的摇晃手势 / 顶部区域悬停
final class DragDetector {
    static let shared = DragDetector()
    static let fileDragDetected = Notification.Name(Constants.NotificationNames.shakeGestureDetected)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var recentPositions: [(point: CGPoint, timestamp: TimeInterval)] = []
    private var lastTriggerTime: TimeInterval = 0
    private var isDragConfirmed: Bool = false  // 当前拖拽已确认是文件拖拽

    private init() {}

    func start() {
        startEventTap()
        startPolling()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
        print("[DragDetector] 已启动")
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

    // MARK: - 轮询

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isLeftMouseButtonDown else {
                if !self.recentPositions.isEmpty { self.recentPositions.removeAll() }
                self.isDragConfirmed = false
                return
            }
            guard self.isDraggingSupportedContent else { return }
            self.handleDrag(at: NSEvent.mouseLocation)
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    // MARK: - CGEventTap

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
            print("[DragDetector] CGEventTap 创建失败（可能缺少辅助功能权限）")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[DragDetector] CGEventTap 已启用")
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDragged:
            guard isDraggingSupportedContent else { break }
            handleDrag(at: event.location)
        case .leftMouseUp:
            recentPositions.removeAll()
            isDragConfirmed = false
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        default: break
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            guard isDraggingSupportedContent else { break }
            handleDrag(at: NSEvent.mouseLocation)
        case .leftMouseUp:
            recentPositions.removeAll()
            isDragConfirmed = false
        default: break
        }
    }

    private func handleDrag(at position: CGPoint) {
        guard isLeftMouseButtonDown, isDraggingSupportedContent else {
            recentPositions.removeAll()
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        recentPositions.append((position, now))
        recentPositions = recentPositions.filter { now - $0.timestamp < 0.6 }

        // 更新 pasteboard change count 防止过期数据重复触发
        _ = isDraggingSupportedContent

        let shakeDetected = detectShake()
        let inTopZone = isInTopTriggerZone(position)
        let shouldTrigger = shakeDetected || inTopZone

        if shouldTrigger, now - lastTriggerTime > 1.5 {  // 冷却 1.5s
            lastTriggerTime = now
            recentPositions.removeAll()
            print("[DragDetector] 触发 (shake:\(shakeDetected), topZone:\(inTopZone))")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.fileDragDetected, object: self)
            }
        }
    }

    // MARK: - 拖拽内容检测

    private var isDraggingSupportedContent: Bool {
        // 已确认的拖拽直接返回 true（同一拖拽操作中 changeCount 不变，避免后续帧误判）
        if isDragConfirmed { return true }

        let pasteboard = NSPasteboard(name: .drag)
        let types = pasteboard.types ?? []
        if types.isEmpty { return false }

        let fileUTIs: Set<String> = [
            "public.file-url", "public.file-contents", "NSFilenamesPboardType",
            "public.png", "public.tiff",
        ]
        if types.contains(where: { fileUTIs.contains($0.rawValue) }) {
            isDragConfirmed = true
            return true
        }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [:]) {
            isDragConfirmed = true
            return true
        }
        return false
    }

    // MARK: - 工具方法

    private var isLeftMouseButtonDown: Bool {
        (NSEvent.pressedMouseButtons & 1) == 1
    }

    private func detectShake() -> Bool {
        guard recentPositions.count >= 3 else { return false }
        var directionChanges = 0
        var prevDir: CGFloat = 0
        for i in 1..<recentPositions.count {
            let dx = recentPositions[i].point.x - recentPositions[i-1].point.x
            let dy = recentPositions[i].point.y - recentPositions[i-1].point.y
            let dt = recentPositions[i].timestamp - recentPositions[i-1].timestamp
            guard hypot(dx, dy) / max(CGFloat(dt), 0.001) > 100, abs(dx) > 3 else { continue }
            let dir: CGFloat = dx > 0 ? 1 : -1
            if prevDir != 0, dir != prevDir { directionChanges += 1 }
            prevDir = dir
        }
        return directionChanges >= 2
    }

    private func isInTopTriggerZone(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return false
        }
        let frame = screen.frame
        let zone = CGRect(x: frame.midX - 100, y: frame.maxY - 48, width: 200, height: 48)
        return zone.contains(point)
    }
}
