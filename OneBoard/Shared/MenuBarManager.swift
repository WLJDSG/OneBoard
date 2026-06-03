import AppKit
import SwiftUI

/// 菜单栏管理器
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem!
    private var clipboardFloatingWindow: NSPanel?
    var onSettings: (() -> Void)?  // 由 App 注入

    private override init() { super.init() }

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let appIcon = NSImage(named: "AppIcon") {
                button.image = appIcon
            } else {
                button.image = createMenuBarIcon()
            }
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = Constants.appName
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            return  // 右键不做任何事
        }
        // 左键 → 弹出菜单
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

        let hostingView = NSHostingView(rootView: ClipboardPopoverView())
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.popoverWidth, height: Constants.popoverHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "历史剪贴板"
        panel.contentView = hostingView
        FloatingWindowManager.positionAtTopRight(panel)
        panel.makeKeyAndOrderFront(nil)
        clipboardFloatingWindow = panel
    }

    func closeClipboardFloatingWindow() {
        clipboardFloatingWindow?.close(); clipboardFloatingWindow = nil
    }

    // MARK: - Actions

    @objc private func openSettings() {
        // 通过回调通知 SwiftUI App 打开设置
        onSettings?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func createMenuBarIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        icon.isTemplate = true; icon.lockFocus()
        let path = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 14, height: 14), xRadius: 3.5, yRadius: 3.5)
        NSColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1.0).setFill(); path.fill()
        icon.unlockFocus(); return icon
    }
}