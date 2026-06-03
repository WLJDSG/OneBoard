import AppKit
import SwiftUI

/// 菜单栏管理器
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem!
    private var clipboardFloatingWindow: NSPanel?
    var onSettings: (() -> Void)?

    private override init() { super.init() }

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = Constants.appName
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            return
        }
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 OneBoard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        }
    }

    // MARK: - 浮动剪贴板窗口

    func showClipboardAsFloatingWindow() {
        if let existing = clipboardFloatingWindow, existing.isVisible {
            existing.close(); clipboardFloatingWindow = nil; return
        }

        let hostingView = ClipboardTrackingHostingView(
            rootView: ClipboardPopoverView(),
            onMouseExit: { [weak self] in
                self?.closeClipboardFloatingWindow()
            }
        )
        hostingView.wantsLayer = true

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.popoverWidth, height: Constants.popoverHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView

        FloatingWindowManager.positionAtTopRight(panel)
        panel.makeKeyAndOrderFront(nil)
        clipboardFloatingWindow = panel
    }

    func closeClipboardFloatingWindow() {
        clipboardFloatingWindow?.close()
        clipboardFloatingWindow = nil
    }

    // MARK: - Actions

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func createMenuBarIcon() -> NSImage {
        let icon = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: Constants.appName)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        icon.isTemplate = true
        return icon
    }
}

/// 带鼠标追踪的 NSHostingView —— 光标离开时触发回调
private final class ClipboardTrackingHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    private var onMouseExit: (() -> Void)?

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    convenience init(rootView: Content, onMouseExit: @escaping () -> Void) {
        self.init(rootView: rootView)
        self.onMouseExit = onMouseExit
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExit?()
    }
}
