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
    static func readRawData(from item: NSPasteboardItem, contentType: ContentType) -> Data? {
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
            if let url = item.string(forType: .fileURL) {
                return url.data(using: .utf8)
            }
            return nil
        }
    }
}