import AppKit

/// 系统服务提供者 — 注册到 Services 菜单
@objc final class TodoServiceProvider: NSObject {

    /// 从服务菜单调用：将选中文字添加到待办
    @objc func addTextToTodo(_ pboard: NSPasteboard, userData: String?, error: UnsafeMutablePointer<NSString?>) {
        guard let items = pboard.pasteboardItems,
              let item = items.first,
              let text = item.string(forType: .string) else {
            error.pointee = "无法读取选中文本" as NSString
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error.pointee = "选中文本为空" as NSString
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        Task { @MainActor in
            TodoListViewModel.shared.addTodo(text: trimmed, sourceAppBundleId: sourceApp)
        }
    }

    /// 注册服务提供者到 NSApp
    static func register() {
        let provider = TodoServiceProvider()
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
        print("[TodoServiceProvider] 系统服务已注册")
    }
}
