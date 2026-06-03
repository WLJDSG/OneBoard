import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 显示/隐藏剪贴板弹出窗口
    static let showClipboard = Self("showClipboard", default: .init(.c, modifiers: [.command, .shift]))
    /// 截图
    static let captureScreenshot = Self("captureScreenshot", default: .init(.a, modifiers: [.command, .shift]))
    /// 显示/隐藏文件暂存架
    static let showFileShelf = Self("showFileShelf", default: .init(.d, modifiers: [.command, .shift]))
}

/// 全局快捷键管理器
final class HotkeyManager {
    private init() {}

    /// 注册所有快捷键
    static func registerAll() {
        KeyboardShortcuts.onKeyDown(for: .showClipboard) {
            MenuBarManager.shared.togglePopover()
        }

        KeyboardShortcuts.onKeyDown(for: .captureScreenshot) {
            print("[Hotkey] 截图快捷键触发")
            Task { @MainActor in
                await ScreenshotViewModel.shared.startCapture()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .showFileShelf) {
            print("[Hotkey] 文件暂存快捷键触发")
            Task { @MainActor in
                FileStagingViewModel.shared.toggleFloatingShelf()
            }
        }
    }
}