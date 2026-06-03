import SwiftUI

/// 淡蓝色主题色板
enum OneBoardColors {
    /// 主色调 - 淡蓝色
    static let primary = Color(red: 0.35, green: 0.65, blue: 0.95)

    /// 主色调浅色变体
    static let primaryLight = Color(red: 0.55, green: 0.78, blue: 0.97)

    /// 主色调深色变体（hover / 按下状态）
    static let primaryDark = Color(red: 0.25, green: 0.55, blue: 0.85)

    /// 背景色
    static let background = Color(nsColor: .controlBackgroundColor)

    /// 次级背景色
    static let secondaryBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)

    /// 文字主色
    static let textPrimary = Color(nsColor: .labelColor)

    /// 文字次级色
    static let textSecondary = Color(nsColor: .secondaryLabelColor)

    /// 分割线颜色
    static let separator = Color(nsColor: .separatorColor)

    /// 置顶高亮色（淡金色）
    static let pinnedHighlight = Color(red: 1.0, green: 0.95, blue: 0.80)

    /// 删除按钮色
    static let destructive = Color(red: 0.95, green: 0.35, blue: 0.35)

    // MARK: - NSColor 版本

    static let nsPrimary = NSColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1.0)
    static let nsPrimaryLight = NSColor(red: 0.55, green: 0.78, blue: 0.97, alpha: 1.0)
    static let nsPrimaryDark = NSColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1.0)
}