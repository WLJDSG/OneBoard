import AppKit
import SwiftUI

private final class TodoSlidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 待办浮动面板窗口管理器（快捷键切换 + 可固定）
@MainActor
final class TodoSlidePanelWindowManager: NSObject {
    static let shared = TodoSlidePanelWindowManager()
    static let panelSize = CGSize(width: 340, height: 540)

    private var triggerPanel: NSPanel?
    private var slidePanel: NSPanel?
    private var slidePanelTrackingView: SlidePanelTrackingHostingView<TodoSlidePanelView>?
    private var retractTimer: Timer?
    private var isEditing: Bool = false
    private var isPinned: Bool = false
    private var retractSuppressUntil: Date = .distantPast
    var shouldSuppressRetract: Bool = false

    /// 是否正在显示
    var isVisible: Bool { slidePanel?.isVisible ?? false }
    var pinned: Bool { isPinned }

    override private init() { super.init() }

    // MARK: - 启动触发区域

    func setupTriggerZone() {
        triggerPanel?.close()
        triggerPanel = nil
    }

    // MARK: - 显示/隐藏

    func show() {
        guard slidePanel == nil || slidePanel?.isVisible == false else { return }

        let panelSize = Self.panelSize

        // 使用自定义 hosting view 处理鼠标跟踪
        let trackingHostingView = SlidePanelTrackingHostingView(
            rootView: TodoSlidePanelView(),
            onMouseEntered: { [weak self] in
                self?.retractTimer?.invalidate()
                self?.retractTimer = nil
            },
            onMouseExited: { [weak self] in
                guard self?.isPinned == false, self?.shouldSuppressRetract == false else { return }
                self?.scheduleRetract()
            }
        )
        trackingHostingView.wantsLayer = true
        slidePanelTrackingView = trackingHostingView

        let panel = TodoSlidePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = trackingHostingView
        panel.isMovableByWindowBackground = true

        FloatingWindowManager.positionAtTopRight(panel, offset: 28)

        // 动画：从右侧轻微滑入
        let finalOrigin = panel.frame.origin
        let startX = finalOrigin.x + 24
        panel.setFrameOrigin(NSPoint(x: startX, y: finalOrigin.y))

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(finalOrigin)
        }

        slidePanel = panel
        retractTimer?.invalidate()
        retractTimer = nil
    }

    func hide() {
        guard let panel = slidePanel else { return }
        retractTimer?.invalidate()
        retractTimer = nil

        let finalX = panel.frame.origin.x + 24
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: finalX, y: panel.frame.origin.y))
        }) { [weak self] in
            Task { @MainActor in
                panel.close()
                self?.slidePanel = nil
                self?.slidePanelTrackingView = nil
                self?.isPinned = false
                self?.retractSuppressUntil = .distantPast
                self?.shouldSuppressRetract = false
            }
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - 自动收起

    func scheduleRetract() {
        guard !isPinned else { return }
        // 检查抑制时间 — 提交待办后短暂抑制自动收起
        if Date() < retractSuppressUntil { return }
        retractTimer?.invalidate()
        let delay = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.todoAutoRetractDelay)
        let seconds = delay > 0 ? delay : 1.0
        retractTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isEditing else { return }
                self.hide()
            }
        }
    }

    /// 在指定秒数内抑制自动收起（用于提交待办后让用户看到结果）
    func suppressRetract(for seconds: TimeInterval = 3.0) {
        retractSuppressUntil = Date().addingTimeInterval(seconds)
    }

    // MARK: - 编辑状态

    func setEditing(_ editing: Bool) {
        isEditing = editing
        if !editing, !isPinned {
            scheduleRetract()
        }
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            retractTimer?.invalidate()
            retractTimer = nil
        } else if isVisible {
            scheduleRetract()
        }
    }

    func focusForEditing() {
        retractTimer?.invalidate()
        retractTimer = nil
        isEditing = true
        NSApp.activate(ignoringOtherApps: true)
        slidePanel?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 滑动面板鼠标跟踪视图

private final class SlidePanelTrackingHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    private var onMouseEntered: (() -> Void)?
    private var onMouseExited: (() -> Void)?

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    convenience init(
        rootView: Content,
        onMouseEntered: @escaping () -> Void,
        onMouseExited: @escaping () -> Void
    ) {
        self.init(rootView: rootView)
        self.onMouseEntered = onMouseEntered
        self.onMouseExited = onMouseExited
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }
}

// MARK: - 触发区域追踪视图

private final class TriggerTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }
}
