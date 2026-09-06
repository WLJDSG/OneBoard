import AppKit
import Foundation

struct FinderFileKind: RawRepresentable, Hashable, CaseIterable {
    let rawValue: String
    init?(rawValue: String) {
        guard rawValue.count <= 32,
              rawValue.range(of: "\\A[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*\\z", options: .regularExpression) != nil else { return nil }
        self.rawValue = rawValue.lowercased()
    }
    static let txt = Self(rawValue: "txt")!
    static let docx = Self(rawValue: "docx")!
    static let xlsx = Self(rawValue: "xlsx")!
    static let allCases = ["txt", "md", "rtf", "xml", "json", "csv", "html", "yaml", "sql", "js", "ts", "py", "swift", "docx", "xlsx"].compactMap(Self.init(rawValue:))
    var title: String {
        let names = ["txt": "文本文档", "md": "Markdown", "rtf": "富文本", "xml": "XML", "json": "JSON", "csv": "CSV 表格", "html": "HTML", "docx": "Word 文档", "xlsx": "Excel 表格"]
        return "\(names[rawValue] ?? rawValue.uppercased()) (.\(rawValue))"
    }
}

struct FinderFileCreationRequest: Equatable {
    static let scheme = "oneboard"
    static let host = "new-file"

    let directoryURL: URL
    let kind: FinderFileKind

    var commandURL: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "directory", value: directoryURL.path),
            URLQueryItem(name: "type", value: kind.rawValue)
        ]
        return components.url
    }

    init(directoryURL: URL, kind: FinderFileKind) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.kind = kind
    }

    init?(commandURL: URL) {
        guard commandURL.scheme == Self.scheme,
              commandURL.host == Self.host,
              let components = URLComponents(url: commandURL, resolvingAgainstBaseURL: false),
              let directoryPath = components.queryItems?.first(where: { $0.name == "directory" })?.value,
              directoryPath.hasPrefix("/"),
              let type = components.queryItems?.first(where: { $0.name == "type" })?.value,
              let kind = FinderFileKind(rawValue: type) else {
            return nil
        }
        self.init(
            directoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true),
            kind: kind
        )
    }

    static func managedDirectories(homeURL: URL, desktopURL: URL? = nil) -> Set<URL> {
        var candidates = [
            URL(fileURLWithPath: "/", isDirectory: true),
            homeURL,
            homeURL.appendingPathComponent("Desktop", isDirectory: true),
            homeURL.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true),
            homeURL.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs/Desktop",
                isDirectory: true
            )
        ]
        if let desktopURL {
            candidates.append(desktopURL)
        }

        return Set(candidates.flatMap { url in
            [url.standardizedFileURL, url.resolvingSymlinksInPath().standardizedFileURL]
        })
    }
}

struct FinderTerminalRequest: Equatable {
    static let scheme = "oneboard"
    static let host = "open-terminal"

    let directoryURL: URL

    var commandURL: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [URLQueryItem(name: "directory", value: directoryURL.path)]
        return components.url
    }

    init(directoryURL: URL) { self.directoryURL = directoryURL.standardizedFileURL }

    init?(commandURL: URL) {
        guard commandURL.scheme == Self.scheme,
              commandURL.host == Self.host,
              let components = URLComponents(url: commandURL, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "directory" })?.value,
              path.hasPrefix("/") else { return nil }
        self.init(directoryURL: URL(fileURLWithPath: path, isDirectory: true))
    }
}

@MainActor
enum FinderTerminalOpener {
    static func open(directoryURL: URL, workspace: NSWorkspace = .shared) {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([directoryURL], withApplicationAt: terminalURL, configuration: configuration) { _, error in
            if let error { print("[FinderTerminal] 打开失败: \(error.localizedDescription)") }
        }
    }
}

enum FinderFileCreator {
    static func create(kind: FinderFileKind, in directoryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let destinationURL = uniqueDestination(kind: kind, in: directoryURL, fileManager: fileManager)
        switch kind.rawValue {
        case "docx":
            try createOfficeArchive(files: docxTemplateFiles, at: destinationURL, fileManager: fileManager)
        case "xlsx":
            try createOfficeArchive(files: xlsxTemplateFiles, at: destinationURL, fileManager: fileManager)
        default:
            let bodies = ["rtf": "{\\rtf1\\ansi\\deff0\n}\n", "json": "{}\n", "xml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n", "html": "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title></title></head><body></body></html>\n"]
            try Data((bodies[kind.rawValue] ?? "").utf8).write(to: destinationURL, options: [.withoutOverwriting])
        }
        return destinationURL
    }

    private static func uniqueDestination(
        kind: FinderFileKind,
        in directoryURL: URL,
        fileManager: FileManager
    ) -> URL {
        var counter = 0
        while true {
            let suffix = counter == 0 ? "" : " \(counter)"
            let candidate = directoryURL.appendingPathComponent("未命名\(suffix).\(kind.rawValue)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private static func createOfficeArchive(
        files: [String: String],
        at destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("oneboard-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        for (path, body) in files {
            let fileURL = temporaryRoot.appendingPathComponent(path)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(body.utf8).write(to: fileURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = temporaryRoot
        process.arguments = ["-qr", destinationURL.path] + files.keys.sorted()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "com.oneboard.mac.file-creation",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "无法生成 \(destinationURL.pathExtension) 文件"]
            )
        }
    }

    private static let docxTemplateFiles: [String: String] = [
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

    private static let xlsxTemplateFiles: [String: String] = [
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
