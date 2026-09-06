import SwiftUI
import AppKit

// MARK: - OneBoard Apple Notes 风格设计令牌

/// 暖白底 + 暖金强调 + 柔阴影 —— 像 Apple Notes
enum OneBoardColors {

    // MARK: 强调色 — 天空蓝 #4A9EF7

    static let accent = Color(red: 0.290, green: 0.620, blue: 0.969)
    static let accentLight = accent.opacity(0.08)
    static let accentMedium = accent.opacity(0.15)

    // MARK: 语义色

    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)

    // MARK: 暖白主题文本色

    static let textPrimary = Color(red: 0.173, green: 0.173, blue: 0.165)
    static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.545)
    static let textTertiary = Color(red: 0.733, green: 0.733, blue: 0.718)

    // MARK: 背景色

    /// 面板底 — 暖白
    static let panelBg = Color(red: 0.996, green: 0.992, blue: 0.969)
    /// 搜索栏/Hover 背景
    static let hoverBg = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.02)
    /// 选中行背景
    static let selectedBg = accent.opacity(0.06)
    /// Header 底
    static let headerBg = Color(red: 0.996, green: 0.992, blue: 0.969).opacity(0.5)

    // MARK: 边框

    /// 面板边框
    static let panelBorder = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.06)
    /// 分割线
    static let divider = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.05)
    /// Header 底线
    static let headerBorder = divider
    /// 搜索栏背景
    static let searchBg = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.025)

    // MARK: 内容区颜色

    static let background = Color(nsColor: .controlBackgroundColor)
    static let surface = hoverBg
    static let border = divider
    static let borderSubtle = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.03)
    static let pinnedHighlight = accent.opacity(0.04)

    // MARK: NSColor

    static let nsAccent = NSColor(red: 0.290, green: 0.620, blue: 0.969, alpha: 1.0)
    static let nsAccentLight = nsAccent.withAlphaComponent(0.08)
    static let nsAccentDark = NSColor(red: 0.8, green: 0.58, blue: 0.1, alpha: 1.0)
}

// MARK: - 间距（8pt 网格）

enum OneBoardSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let twoXL: CGFloat = 24
    static let threeXL: CGFloat = 32
    static let twoXS: CGFloat = 4
}

// MARK: - 圆角（Apple Notes 风格：柔和圆角）

enum OneBoardRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 10
    static let twoXL: CGFloat = 14
    static let pill: CGFloat = 8
}

// MARK: - 阴影（Apple Notes：极柔）

enum OneBoardShadow {
    static let sm = (color: Color.black.opacity(0.04), radius: CGFloat(3), y: CGFloat(1))
    static let md = (color: Color.black.opacity(0.05), radius: CGFloat(6), y: CGFloat(2))
    static let lg = (color: Color.black.opacity(0.04), radius: CGFloat(12), y: CGFloat(4))
}

// MARK: - 字体

enum OneBoardFont {
    static let title = Font.system(size: 15, weight: .semibold)
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let callout = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionSmall = Font.system(size: 10, weight: .regular)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let titleLarge = Font.system(size: 20, weight: .bold, design: .serif)
    static let monoBody = mono
    static let monoCaption = Font.system(size: 10, weight: .regular, design: .monospaced)
}
