import AppKit

/// NSPasteboard 类型映射工具
enum PasteboardTypeMapper {

    /// 剪贴板内容类型
    enum ContentType: String, CaseIterable {
        case text
        case rtf
        case html
        case image
        case fileURL

        var displayName: String {
            switch self {
            case .text: return "文本"
            case .rtf: return "富文本"
            case .html: return "HTML"
            case .image: return "图片"
            case .fileURL: return "文件"
            }
        }

        var iconName: String {
            switch self {
            case .text: return "text.alignleft"
            case .rtf: return "doc.richtext"
            case .html: return "chevron.left.forwardslash.chevron.right"
            case .image: return "photo"
            case .fileURL: return "doc"
            }
        }
    }

    /// 从 NSPasteboardItem 推断内容类型
    /// 优先级：fileURL > image > html > rtf > text
    static func inferContentType(from item: NSPasteboardItem) -> ContentType? {
        let types = item.types

        if types.contains(.fileURL) || types.contains(.fileContents) {
            return .fileURL
        }
        if types.contains(.png) || types.contains(.tiff) {
            return .image
        }
        if types.contains(.html) {
            return .html
        }
        if types.contains(.rtf) || types.contains(.rtfd) {
            return .rtf
        }
        if types.contains(.string) {
            return .text
        }
        return nil
    }

    /// 从剪贴板读取纯文本
    static func readPlainText(from item: NSPasteboardItem) -> String? {
        if let text = item.string(forType: .string) {
            return text
        }
        if let rtfData = item.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            return attributed.string
        }
        if let htmlData = item.data(forType: .html),
           let attributed = NSAttributedString(html: htmlData, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }

    /// 从剪贴板项读取原始数据
    /// - Parameters:
    ///   - item: 剪贴板项
    ///   - contentType: 内容类型
    ///   - pasteboard: 当前剪贴板（用于读取完整 URL 对象，解析文件引用 URL）
    static func readRawData(from item: NSPasteboardItem, contentType: ContentType, pasteboard: NSPasteboard? = nil) -> Data? {
        switch contentType {
        case .text:
            if let text = item.string(forType: .string) {
                return text.data(using: .utf8)
            }
            return nil
        case .rtf:
            return item.data(forType: .rtf)
        case .html:
            return item.data(forType: .html)
        case .image:
            // 优先读取 PNG，其次 TIFF
            if let pngData = item.data(forType: .png) {
                return pngData
            }
            if let tiffData = item.data(forType: .tiff) {
                return tiffData
            }
            return nil
        case .fileURL:
            // 优先从 pasteboard 读取 NSURL 对象，可正确解析 file:///.file/id=... 等文件引用 URL
            if let pb = pasteboard,
               let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let firstURL = urls.first {
                // 使用 standardizedFileURL 解析符号链接和文件引用，得到实际路径
                let resolved = firstURL.standardizedFileURL
                return resolved.path.data(using: .utf8)
            }
            // 回退：从 item 读取 fileURL 字符串
            if let urlString = item.string(forType: .fileURL) {
                // 如果是标准 file:// URL，解析出路径；否则直接存
                if urlString.hasPrefix("file://") {
                    // 尝试解析为 URL 再取路径，避免存储 file:///.file/id=... 这类引用 URL
                    if let url = URL(string: urlString) {
                        let resolved = url.standardizedFileURL
                        // 如果解析成功且是实际路径（非 /.file/id=...），使用解析后的路径
                        if !resolved.path.hasPrefix("/.file/") {
                            return resolved.path.data(using: .utf8)
                        }
                    }
                }
                return urlString.data(using: .utf8)
            }
            return nil
        }
    }
}