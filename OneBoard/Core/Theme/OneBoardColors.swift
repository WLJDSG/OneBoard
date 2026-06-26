import SwiftUI
import AppKit

// MARK: - OneBoard Warm Minimal 设计令牌 v3.0

/// Warm Minimal 品牌色 / 语义色 / 间距 / 圆角 / 阴影 统一设计令牌
enum OneBoardColors {

    // MARK: 品牌暖色

    /// 主强调色 — 暖琥珀 #D4792E
    static let accent = Color(red: 0.831, green: 0.475, blue: 0.180)

    /// 浅色变体 — hover 背景、选中行
    static let accentLight = accent.opacity(0.10)

    /// 深色变体 — 按下态
    static let accentDark = Color(red: 0.710, green: 0.396, blue: 0.122)

    // MARK: 语义色

    /// 成功 — 暖绿
    static let success = Color(red: 0.420, green: 0.620, blue: 0.427)

    /// 警告
    static let warning = Color(red: 0.831, green: 0.627, blue: 0.235)

    /// 错误 / 删除 — 暖红
    static let destructive = Color(red: 0.788, green: 0.353, blue: 0.290)

    // MARK: 中性色（系统自适应 → 自动支持深色模式）

    /// 主要文字
    static let textPrimary = Color(nsColor: .labelColor)

    /// 次要文字 / 描述
    static let textSecondary = Color(nsColor: .secondaryLabelColor)

    /// 三级文字 / 占位符 / 禁用
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    /// 表面色 — 卡片、输入框背景
    static let surface = Color(nsColor: .controlBackgroundColor)

    // MARK: 旧版兼容别名

    static let background = surface
    static let border = Color(nsColor: .separatorColor)
    static let borderSubtle = Color(nsColor: .separatorColor).opacity(0.5)
    static let pinnedHighlight = accentLight

    static let primary = accent
    static let primaryLight = accentLight
    static let primaryDark = accentDark
    static let secondaryBackground = surface.opacity(0.5)
    static let separator = Color(nsColor: .separatorColor)

    // MARK: NSColor 版本（AppKit 桥接）

    static let nsAccent = NSColor(red: 0.831, green: 0.475, blue: 0.180, alpha: 1.0)
    static let nsAccentLight = nsAccent.withAlphaComponent(0.10)
    static let nsAccentDark = NSColor(red: 0.710, green: 0.396, blue: 0.122, alpha: 1.0)

    static let nsPrimary = nsAccent
    static let nsPrimaryLight = nsAccentLight
    static let nsPrimaryDark = nsAccentDark
}

// MARK: - 间距系统（8pt 网格）

enum OneBoardSpacing {
    /// 4pt
    static let xs: CGFloat = 4
    /// 8pt
    static let sm: CGFloat = 8
    /// 12pt
    static let md: CGFloat = 12
    /// 16pt
    static let lg: CGFloat = 16
    /// 20pt
    static let xl: CGFloat = 20
    /// 24pt
    static let twoXL: CGFloat = 24
    /// 32pt
    static let threeXL: CGFloat = 32
    /// 兼容别名
    static let twoXS: CGFloat = 4
}

// MARK: - 圆角系统

enum OneBoardRadius {
    /// 6pt — 按钮、标签、行
    static let sm: CGFloat = 6
    /// 8pt — 卡片、输入框、搜索栏
    static let md: CGFloat = 8
    /// 12pt — 浮动面板
    static let lg: CGFloat = 12
    /// 旧版兼容
    static let xl: CGFloat = 12
    static let twoXL: CGFloat = 16
}

// MARK: - 阴影系统（暖灰，非纯黑）

enum OneBoardShadow {
    /// 小阴影 — 卡片、hover
    static let sm = (color: Color.black.opacity(0.05), radius: CGFloat(4), y: CGFloat(2))
    /// 中阴影 — 小面板
    static let md = (color: Color.black.opacity(0.07), radius: CGFloat(8), y: CGFloat(3))
    /// 大阴影 — 大面板
    static let lg = (color: Color.black.opacity(0.08), radius: CGFloat(14), y: CGFloat(4))
}

// MARK: - 字体系统

enum OneBoardFont {
    /// 面板标题 — 17pt semibold
    static let title = Font.system(size: 17, weight: .semibold)
    /// 区块标题 — 14pt semibold
    static let headline = Font.system(size: 14, weight: .semibold)
    /// 正文 — 13pt regular
    static let body = Font.system(size: 13, weight: .regular)
    /// 辅助信息 — 11pt regular
    static let caption = Font.system(size: 11, weight: .regular)
    /// 小标签 — 10pt regular
    static let captionSmall = Font.system(size: 10, weight: .regular)
    /// 等宽 — 12pt mono
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// 旧版兼容
    static let titleLarge = Font.system(size: 20, weight: .bold, design: .serif)
    static let callout = Font.system(size: 12, weight: .medium)
    static let monoBody = mono
    static let monoCaption = Font.system(size: 10, weight: .regular, design: .monospaced)
}
