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

    /// CGEventTap 是否可用（需要辅助功能权限）
    private var eventTapAvailable: Bool = false
    /// 是否已向用户提示过需要辅助功能权限
    private var hasPromptedForAccessibility: Bool = false

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

    // MARK: - 高频轮询（30ms 间隔，作为 CGEventTap 的补充和兜底）

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            let position = NSEvent.mouseLocation
            // 仅当左键按住 + 拖拽内容为文件类型时检测，避免空拖拽或纯文本拖拽误触发
            if self.isLeftMouseButtonDown, self.isDraggingSupportedContent {
                self.handleDrag(at: position)
            } else if !self.recentPositions.isEmpty {
                // 如果之前有轨迹但左键已松开，清理轨迹
                if !self.isLeftMouseButtonDown {
                    self.recentPositions.removeAll()
                }
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
            print("[DragDetector] CGEventTap 创建失败（可能缺少辅助功能权限），使用轮询模式兜底")
            eventTapAvailable = false
            // 延迟 2 秒后提示用户开启辅助功能（避免 App 启动时立即弹窗）
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, !self.eventTapAvailable, !self.hasPromptedForAccessibility,
                      !PermissionManager.shared.hasAccessibilityPermission else { return }
                self.hasPromptedForAccessibility = true
                print("[DragDetector] 提示用户开启辅助功能权限")
                PermissionManager.shared.promptAccessibilityPermission()
            }
            return
        }

        eventTap = tap
        eventTapAvailable = true
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[DragDetector] CGEventTap 已启用")
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDragged:
            // 忽略拖动窗口（非文件拖拽）的事件：拖拽粘贴板无内容时跳过
            // 避免用户拖动任意窗口时触发暂存区检测
            guard isDraggingSupportedContent else { break }
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
            // 仅当拖拽内容为文件类型时才处理，过滤窗口拖动
            guard isDraggingSupportedContent else { break }
            handleDrag(at: NSEvent.mouseLocation)
        case .leftMouseUp:
            recentPositions.removeAll()
        default:
            break
        }
    }

    private func handleDrag(at position: CGPoint) {
        // 必须是左键按住 + 拖拽文件类型内容，否则不处理
        guard isLeftMouseButtonDown, isDraggingSupportedContent else {
            recentPositions.removeAll()
            return
        }

        let inTopZone = isInTopTriggerZone(position)
        let isDragging = isDraggingSupportedContent

        let now = Date().timeIntervalSinceReferenceDate
        recentPositions.append((position, now))
        // 保留最近 0.6s 的轨迹
        recentPositions = recentPositions.filter { now - $0.timestamp < 0.6 }

        // 放宽触发条件：摇动检测 OR 顶部区域（拖拽内容时）
        let shakeDetected = detectShake()
        let shouldTrigger = (shakeDetected && isDragging) || (inTopZone && isDragging)

        if shouldTrigger, now - lastTriggerTime > 1.2 {
            lastTriggerTime = now
            recentPositions.removeAll()
            print("[DragDetector] 检测到拖拽手势 (shake: \(shakeDetected), topZone: \(inTopZone))")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.fileDragDetected, object: self)
            }
        }
    }

    private var isDraggingSupportedContent: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let types = pasteboard.types ?? []
        if types.isEmpty { return false }

        // 仅检测文件/图片/URL 类型的拖拽，排除纯文本等非文件内容
        // public.file-url 和 NSFilenamesPboardType 表示拖拽的是文件
        // public.url 可能是网页链接或文件引用
        // public.tiff / public.png 可能是从 Finder 拖拽的图片
        let supportedNames = [
            "public.file-url",
            "NSFilenamesPboardType",
            "public.tiff",
            "public.png"
        ]

        let isSupported = types.contains { type in
            supportedNames.contains(type.rawValue)
                || type.rawValue.localizedCaseInsensitiveContains("file")
        }

        // 额外检查：如果拖拽粘贴板中包含文件 URL，肯定是文件拖拽
        if !isSupported {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                return true
            }
        }

        return isSupported
    }

    private var isLeftMouseButtonDown: Bool {
        (NSEvent.pressedMouseButtons & 1) == 1
    }

    /// 检测左右摇晃（放宽条件）
    private func detectShake() -> Bool {
        guard recentPositions.count >= 3 else { return false }

        var directionChanges = 0
        var previousDirection: CGFloat = 0

        for index in 1..<recentPositions.count {
            let previous = recentPositions[index - 1]
            let current = recentPositions[index]
            let dx = current.point.x - previous.point.x
            let dy = current.point.y - previous.point.y
            let dt = current.timestamp - previous.timestamp
            let speed = hypot(dx, dy) / max(CGFloat(dt), 0.001)

            // 降低速度和位移阈值
            guard speed > 100, abs(dx) > 3 else { continue }

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
        let zoneWidth: CGFloat = 200
        let zoneHeight: CGFloat = 48
        let zone = CGRect(
            x: frame.midX - zoneWidth / 2,
            y: frame.maxY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )
        return zone.contains(point)
    }
}
