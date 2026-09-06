import FinderSync
import Cocoa
import Darwin

/// Finder Sync 扩展主控制器
@objc(FinderSyncController)
final class FinderSyncController: FIFinderSync {
    private static let actualHomeURL: URL = {
        guard let user = getpwuid(getuid()), let home = user.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
    }()

    private static let actualDesktopURL = actualHomeURL.appendingPathComponent("Desktop", isDirectory: true)
    private static let resolvedDesktopURL = FileManager.default.urls(
        for: .desktopDirectory,
        in: .userDomainMask
    ).first

    private var currentMenuKind: FIMenuKind?

    override init() {
        super.init()
        // 根目录覆盖所有本地卷路径，home/desktop 兼容 macOS 26 的桌面空白处菜单。
        FIFinderSyncController.default().directoryURLs = FinderFileCreationRequest.managedDirectories(
            homeURL: Self.actualHomeURL,
            desktopURL: Self.resolvedDesktopURL
        )
        print("[FinderSync] 扩展已初始化")
    }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // 在桌面/文件夹空白处、选中文件项和工具栏菜单中显示。
        switch menuKind {
        case .contextualMenuForContainer, .contextualMenuForItems, .toolbarItemMenu:
            break
        default:
            return nil
        }
        currentMenuKind = menuKind

        let menu = NSMenu(title: "")

        let terminalItem = NSMenuItem(title: "在当前路径打开终端", action: #selector(openTerminalHere), keyEquivalent: "")
        terminalItem.target = self
        terminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        menu.addItem(terminalItem)

        // 读取启用的文件类型（从共享 UserDefaults）
        let shared = UserDefaults(suiteName: "group.com.oneboard.mac")
        let enabledTypes = shared?.stringArray(forKey: "enabled_file_types") ?? ["txt", "docx", "xlsx"]

        // 新建文件子菜单
        let newFileSubmenu = NSMenu(title: "新建文件")

        for kind in enabledTypes.compactMap(FinderFileKind.init(rawValue:)) {
            let item = NSMenuItem(title: kind.title, action: #selector(createCustomFile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            newFileSubmenu.addItem(item)
        }

        if newFileSubmenu.items.contains(where: { !$0.isSeparatorItem }) {
            let mainItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            mainItem.submenu = newFileSubmenu
            mainItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            menu.addItem(mainItem)
        }

        return menu
    }

    // MARK: - 文件创建

    @objc private func createCustomFile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = FinderFileKind(rawValue: raw) else { return }
        requestFileCreation(kind: kind)
    }

    @objc private func openTerminalHere() {
        guard let targetURL = targetDirectoryURL() else {
            showCreationFailure("无法获取 Finder 当前目录。请在文件夹空白处右键，或先选中文件夹后重试。")
            return
        }
        let request = FinderTerminalRequest(directoryURL: targetURL)
        guard let commandURL = request.commandURL, NSWorkspace.shared.open(commandURL) else {
            showCreationFailure("无法唤起 OneBoard 主应用。请确认 OneBoard 已正确安装后重试。")
            return
        }
    }

    private func requestFileCreation(kind: FinderFileKind) {
        guard let targetURL = targetDirectoryURL() else {
            print("[FinderSync] 无法获取目标目录")
            showCreationFailure("无法获取 Finder 当前目录。请在文件夹空白处右键，或先选中文件夹后重试。")
            return
        }
        let request = FinderFileCreationRequest(directoryURL: targetURL, kind: kind)
        guard let commandURL = request.commandURL, NSWorkspace.shared.open(commandURL) else {
            showCreationFailure("无法唤起 OneBoard 主应用。请确认 OneBoard 已正确安装后重试。")
            return
        }
        print("[FinderSync] 已请求主应用创建 \(kind.rawValue) 文件: \(targetURL.path)")
    }

    private func targetDirectoryURL() -> URL? {
        let controller = FIFinderSyncController.default()
        if let targetURL = controller.targetedURL() {
            return directoryURL(for: targetURL)
        }

        guard let selectedURL = controller.selectedItemURLs()?.first else {
            // 桌面空白处右键时，Finder 可能不提供 targetedURL/selectedItemURLs。
            // 仅容器菜单回退到桌面，避免工具栏操作误建到桌面。
            guard currentMenuKind == .contextualMenuForContainer else { return nil }
            return Self.actualDesktopURL
        }

        return directoryURL(for: selectedURL)
    }

    private func directoryURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func showCreationFailure(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "OneBoard 新建文件失败"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

}
