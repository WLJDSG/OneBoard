import FinderSync
import Cocoa

/// Finder Sync 扩展主控制器
final class FinderSyncController: FIFinderSync {

    override init() {
        super.init()
        // 监控用户整个文件系统
        FIFinderSyncController.default().directoryURLs = Set([
            URL(fileURLWithPath: "/")
        ])
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

        let menu = NSMenu(title: "")

        // 读取启用的文件类型（从共享 UserDefaults）
        let shared = UserDefaults(suiteName: "group.com.oneboard.mac")
        let enabledTypes = shared?.stringArray(forKey: "enabled_file_types") ?? ["txt", "docx", "xlsx"]

        // 新建文件子菜单
        let newFileSubmenu = NSMenu(title: "新建文件")

        if enabledTypes.contains("txt") {
            let item = NSMenuItem(title: "新建文本文档 (.txt)", action: #selector(createTXTFile), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            newFileSubmenu.addItem(item)
        }

        if enabledTypes.contains("docx") {
            let item = NSMenuItem(title: "新建 Word 文档 (.docx)", action: #selector(createDOCXFile), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
            newFileSubmenu.addItem(item)
        }

        if enabledTypes.contains("xlsx") {
            let item = NSMenuItem(title: "新建 Excel 表格 (.xlsx)", action: #selector(createXLSXFile), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
            newFileSubmenu.addItem(item)
        }

        guard newFileSubmenu.items.contains(where: { !$0.isSeparatorItem }) else {
            return nil
        }

        let mainItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        mainItem.submenu = newFileSubmenu
        mainItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        menu.addItem(mainItem)

        return menu
    }

    // MARK: - 文件创建

    @objc private func createTXTFile() {
        createFile(extension: "txt", content: Data())
    }

    @objc private func createDOCXFile() {
        createOfficeFile(extension: "docx", files: docxTemplateFiles)
    }

    @objc private func createXLSXFile() {
        createOfficeFile(extension: "xlsx", files: xlsxTemplateFiles)
    }

    private func createFile(extension ext: String, content: Data) {
        guard let targetURL = targetDirectoryURL() else {
            print("[FinderSync] 无法获取目标目录")
            showCreationFailure("无法获取 Finder 当前目录。请在文件夹空白处右键，或先选中文件夹后重试。")
            return
        }

        let baseName = "未命名"
        var fileName = "\(baseName).\(ext)"
        var counter = 1
        let fm = FileManager.default

        while fm.fileExists(atPath: targetURL.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(counter).\(ext)"
            counter += 1
        }

        let fileURL = targetURL.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, options: [.withoutOverwriting])
            // 在 Finder 中选中新文件并进入重命名状态
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            print("[FinderSync] 已创建文件: \(fileURL.path)")
        } catch {
            print("[FinderSync] 创建 \(ext) 文件失败: \(error)")
            showCreationFailure("无法在“\(targetURL.lastPathComponent)”中新建文件。\n\n\(error.localizedDescription)")
        }
    }

    private func createOfficeFile(extension ext: String, files: [String: String]) {
        guard let targetURL = targetDirectoryURL() else {
            print("[FinderSync] 无法获取目标目录")
            showCreationFailure("无法获取 Finder 当前目录。请在文件夹空白处右键，或先选中文件夹后重试。")
            return
        }

        let baseName = "未命名"
        var fileName = "\(baseName).\(ext)"
        var counter = 1
        let fm = FileManager.default

        while fm.fileExists(atPath: targetURL.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(counter).\(ext)"
            counter += 1
        }

        let fileURL = targetURL.appendingPathComponent(fileName)
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oneboard-\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempRoot) }

            for (path, body) in files {
                let url = tempRoot.appendingPathComponent(path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try body.data(using: .utf8)?.write(to: url)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = tempRoot
            process.arguments = ["-qr", fileURL.path] + Array(files.keys).sorted()
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(domain: "OneBoardFinderSync", code: Int(process.terminationStatus))
            }

            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            print("[FinderSync] 已创建文件: \(fileURL.path)")
        } catch {
            print("[FinderSync] 创建 \(ext) 文件失败: \(error)")
            showCreationFailure("无法在“\(targetURL.lastPathComponent)”中新建 \(ext) 文件。\n\n\(error.localizedDescription)")
        }
    }

    private func targetDirectoryURL() -> URL? {
        let controller = FIFinderSyncController.default()
        if let targetURL = controller.targetedURL() {
            return targetURL
        }

        guard let selectedURL = controller.selectedItemURLs()?.first else {
            return nil
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return selectedURL
        }

        return selectedURL.deletingLastPathComponent()
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

    private var docxTemplateFiles: [String: String] {
        [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
            """,
            "word/document.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/><w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
            """
        ]
    }

    private var xlsxTemplateFiles: [String: String] {
        [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>
            """
        ]
    }
}
