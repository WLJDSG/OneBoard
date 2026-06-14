import Foundation
import GRDB

/// 暂存文件模型
struct StagedFile: Codable, Identifiable {
    var id: Int64?
    var fileName: String
    var fileURL: String          // 文件绝对路径
    var fileSize: Int64
    var bookmarkData: Data?      // 安全域书签
    var thumbnailData: Data?     // 缩略图 PNG
    var stagedAt: Date

    /// 从 URL 创建
    init(url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        self.fileName = url.lastPathComponent
        self.fileURL = url.path
        self.fileSize = Int64(resourceValues.fileSize ?? 0)
        self.stagedAt = Date()
        self.thumbnailData = FileIconProvider.thumbnail(
            for: url,
            size: NSSize(width: 96, height: 96)
        )?.pngData
    }
}

// MARK: - GRDB Record

extension StagedFile: FetchableRecord, PersistableRecord {
    static let databaseTableName = "staged_files"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let fileName = Column(CodingKeys.fileName)
        static let fileURL = Column(CodingKeys.fileURL)
        static let fileSize = Column(CodingKeys.fileSize)
        static let bookmarkData = Column(CodingKeys.bookmarkData)
        static let thumbnailData = Column(CodingKeys.thumbnailData)
        static let stagedAt = Column(CodingKeys.stagedAt)
    }
}
