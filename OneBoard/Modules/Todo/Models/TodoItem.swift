import Foundation
import GRDB
import SwiftUI

/// 优先级
enum Priority: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    /// 排序权重（数字越小越靠前）
    var sortOrder: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .high:   return "高"
        case .medium: return "中"
        case .low:    return "低"
        }
    }

    /// 对应颜色
    var color: Color {
        switch self {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .gray
        }
    }
}

/// 待办事项模型
struct TodoItem: Codable, Identifiable {
    var id: Int64?
    var text: String
    var isCompleted: Bool
    var priority: Priority
    var sourceAppBundleId: String?
    var dueDate: Date?
    var completedAt: Date?
    var createdAt: Date

    // MARK: - Computed Properties

    /// 是否已过期（未完成且截止日期已过）
    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Date()
    }

    /// 来源应用显示名称
    var sourceAppName: String? {
        guard let bundleId = sourceAppBundleId else { return nil }
        // 常见应用映射
        let knownApps: [String: String] = [
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Chrome",
            "com.microsoft.VSCode": "VS Code",
            "com.microsoft.Word": "Word",
            "com.microsoft.Excel": "Excel",
            "com.apple.Notes": "备忘录",
            "com.apple.mail": "邮件",
            "com.apple.iChat": "信息",
            "com.tencent.WeWorkMac": "企业微信",
            "com.tencent.xinWeChat": "微信",
        ]
        if let name = knownApps[bundleId] { return name }
        // 从 Bundle ID 最后一段提取
        return bundleId.components(separatedBy: ".").last
    }

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        text: String,
        isCompleted: Bool = false,
        priority: Priority = .medium,
        sourceAppBundleId: String? = nil,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.priority = priority
        self.sourceAppBundleId = sourceAppBundleId
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Record

extension TodoItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "todos"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let text = Column(CodingKeys.text)
        static let isCompleted = Column(CodingKeys.isCompleted)
        static let priority = Column(CodingKeys.priority)
        static let sourceAppBundleId = Column(CodingKeys.sourceAppBundleId)
        static let dueDate = Column(CodingKeys.dueDate)
        static let completedAt = Column(CodingKeys.completedAt)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
