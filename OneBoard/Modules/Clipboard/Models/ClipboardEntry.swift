import AppKit
import GRDB

/// 剪贴板历史条目模型
struct ClipboardEntry: Codable, Identifiable {
    var id: Int64?
    var contentType: String          // "text" / "rtf" / "html" / "image" / "fileURL"
    var plainText: String?           // 纯文本缓存，用于搜索和预览
    var data: Data                   // 原始剪贴板数据
    var sourceAppBundleId: String?   // 来源应用 Bundle ID
    var isPinned: Bool
    var createdAt: Date

    // MARK: - Computed Properties

    var contentTypeEnum: PasteboardTypeMapper.ContentType? {
        PasteboardTypeMapper.ContentType(rawValue: contentType)
    }

    /// 预览文本（截取前 100 个字符）
    var previewText: String {
        if let text = plainText, !text.isEmpty {
            let trimmed = text.replacingOccurrences(of: "\n", with: " ")
            return String(trimmed.prefix(100))
        }
        return contentTypeEnum?.displayName ?? "未知内容"
    }

    /// 是否为图片类型
    var isImage: Bool {
        contentType == "image"
    }

    /// 从图片数据创建 NSImage
    var nsImage: NSImage? {
        guard isImage else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        contentType: String,
        plainText: String? = nil,
        data: Data,
        sourceAppBundleId: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contentType = contentType
        self.plainText = plainText
        self.data = data
        self.sourceAppBundleId = sourceAppBundleId
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Record

extension ClipboardEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_history"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let contentType = Column(CodingKeys.contentType)
        static let plainText = Column(CodingKeys.plainText)
        static let data = Column(CodingKeys.data)
        static let sourceAppBundleId = Column(CodingKeys.sourceAppBundleId)
        static let isPinned = Column(CodingKeys.isPinned)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    /// 插入后更新 FTS 索引
    func didInsert(_ inserted: InsertionSuccess) {
        // FTS 索引更新在 Repository 层处理
    }
}