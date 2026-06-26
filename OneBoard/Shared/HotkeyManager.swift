import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 显示/隐藏剪贴板弹出窗口
    static let showClipboard = Self("showClipboard", default: .init(.v, modifiers: [.option]))
    /// 截图
    static let captureScreenshot = Self("captureScreenshot", default: .init(.a, modifiers: [.option]))
    /// 翻译当前选中的文字
    static let translateSelectedText = Self("translateSelectedText", default: .init(.a, modifiers: [.option, .shift]))
    /// 显示/隐藏文件暂存架
    static let showFileShelf = Self("showFileShelf", default: .init(.d, modifiers: [.command, .shift]))
    /// 显示/隐藏网关切换小窗
    static let showGatewaySwitcher = Self("showGatewaySwitcher", default: .init(.g, modifiers: [.command, .shift]))
    /// 显示/隐藏待办面板
    static let toggleTodoPanel = Self("toggleTodoPanel", default: .init(.t, modifiers: [.command, .option]))
    /// 将选中文字添加到待办
    static let addSelectedTextToTodo = Self("addSelectedTextToTodo", default: .init(.t, modifiers: [.command, .shift, .option]))
}

/// 全局快捷键管理器
final class HotkeyManager {
    private init() {}

    /// 注册所有快捷键
    static func registerAll() {
        migrateDefaultShortcutsIfNeeded()

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

        KeyboardShortcuts.onKeyDown(for: .toggleTodoPanel) {
            print("[Hotkey] 待办面板快捷键触发")
            Task { @MainActor in
                TodoSlidePanelWindowManager.shared.toggle()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .addSelectedTextToTodo) {
            print("[Hotkey] 添加选中文字到待办")
            Task { @MainActor in
                TodoListViewModel.shared.addSelectedTextFromFrontmostApp()
            }
        }
    }

    private static func migrateDefaultShortcutsIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "OneBoardHotkeyDefaultMigrationVersion"
        guard defaults.integer(forKey: migrationKey) < 1 else { return }

        migrateShortcut(
            name: .showClipboard,
            oldDefault: .init(.c, modifiers: [.command, .shift]),
            newDefault: .init(.v, modifiers: [.option])
        )
        migrateShortcut(
            name: .captureScreenshot,
            oldDefault: .init(.a, modifiers: [.command, .shift]),
            newDefault: .init(.a, modifiers: [.option])
        )
        migrateShortcut(
            name: .translateSelectedText,
            oldDefault: .init(.t, modifiers: [.command, .shift]),
            newDefault: .init(.a, modifiers: [.option, .shift])
        )

        defaults.set(1, forKey: migrationKey)
    }

    private static func migrateShortcut(
        name: KeyboardShortcuts.Name,
        oldDefault: KeyboardShortcuts.Shortcut,
        newDefault: KeyboardShortcuts.Shortcut
    ) {
        let current = KeyboardShortcuts.getShortcut(for: name)
        if current == nil || current == oldDefault {
            KeyboardShortcuts.setShortcut(newDefault, for: name)
        }
    }
}
