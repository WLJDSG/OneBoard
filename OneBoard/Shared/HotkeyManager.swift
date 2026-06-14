import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 显示/隐藏剪贴板弹出窗口
    static let showClipboard = Self("showClipboard", default: .init(.c, modifiers: [.command, .shift]))
    /// 截图
    static let captureScreenshot = Self("captureScreenshot", default: .init(.a, modifiers: [.command, .shift]))
    /// 翻译当前选中的文字
    static let translateSelectedText = Self("translateSelectedText", default: .init(.t, modifiers: [.command, .shift]))
    /// 显示/隐藏文件暂存架
    static let showFileShelf = Self("showFileShelf", default: .init(.d, modifiers: [.command, .shift]))
    /// 显示/隐藏网关切换小窗
    static let showGatewaySwitcher = Self("showGatewaySwitcher", default: .init(.g, modifiers: [.command, .shift]))
}

/// 全局快捷键管理器
final class HotkeyManager {
    private init() {}

    /// 注册所有快捷键
    static func registerAll() {
        KeyboardShortcuts.onKeyDown(for: .showClipboard) {
            // 快捷键呼出 → 独立浮动窗口（不依赖图标）
            MenuBarManager.shared.showClipboardAsFloatingWindow()
        }

        KeyboardShortcuts.onKeyDown(for: .captureScreenshot) {
            print("[Hotkey] 截图快捷键触发")
            Task { @MainActor in
                await ScreenshotViewModel.shared.startCapture()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .translateSelectedText) {
            print("[Hotkey] 翻译选中文字快捷键触发")
            Task { @MainActor in
                await ScreenshotViewModel.shared.translateSelectedText()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .showFileShelf) {
            print("[Hotkey] 文件暂存快捷键触发")
            Task { @MainActor in
                FileStagingViewModel.shared.toggleFloatingShelf()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .showGatewaySwitcher) {
            print("[Hotkey] 网关切换快捷键触发")
            Task { @MainActor in
                MenuBarManager.shared.toggleGatewaySwitcherPanel()
            }
        }
    }
}
