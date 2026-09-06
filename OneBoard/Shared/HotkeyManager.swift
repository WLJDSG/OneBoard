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

    /// 统一由可视化键位注册，避免旧快捷键重复触发。
    static func registerAll() {
        Task { @MainActor in QuickLaunchBindings.register() }
    }
}
