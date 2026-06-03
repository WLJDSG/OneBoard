import AppKit
import SwiftUI

/// 菜单栏管理器
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    /// 打开 Popover 前的前台应用，关闭时恢复
    private var previousApp: NSRunningApplication?

    private override init() {
        super.init()
    }

    /// 设置菜单栏（AppDelegate 中调用）
    func setup() {
        // 状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.on.square",
                accessibilityDescription: "OneBoard"
            )
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = Constants.appName
        }

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: ClipboardPopoverView()
        )
    }

    /// 切换 Popover 显示/隐藏
    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            // 关闭后恢复之前的前台应用
            restorePreviousApp()
        } else {
            // 保存当前前台应用
            previousApp = NSWorkspace.shared.frontmostApplication
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 激活应用，确保输入框能获得焦点
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 恢复 Popover 打开前的前台应用
    func restorePreviousApp() {
        guard let app = previousApp else { return }
        app.activate()
        print("[MenuBarManager] 已激活原应用: \(app.localizedName ?? "未知")")
        previousApp = nil
    }
}