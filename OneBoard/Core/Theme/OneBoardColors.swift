import SwiftUI
import AppKit

// MARK: - OneBoard 设计令牌 — 精确匹配 HTML 设计图

/// 深色主题令牌（固定色值，不跟随系统外观切换）
/// HTML 基准：body #1c1c1e, panel rgba(255,255,255,.06)
enum OneBoardColors {

    // MARK: 强调色 — 天空蓝 #4A9EF7

    static let accent = Color(red: 0.290, green: 0.620, blue: 0.969)
    static let accentLight = accent.opacity(0.12)

    // MARK: 语义色（系统自适应）

    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)

    // MARK: 深色主题文本色（匹配 HTML）

    /// 主要文字 — HTML body color #f2f2f7
    static let textPrimary = Color(red: 0.949, green: 0.949, blue: 0.969)
    /// 次要文字 — HTML #8e8e93
    static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.576)
    /// 三级文字 — HTML #636366
    static let textTertiary = Color(red: 0.388, green: 0.388, blue: 0.400)

    // MARK: 深色主题背景色（匹配 HTML rgba 值）

    /// 面板底 — HTML rgba(255,255,255,.06) on #1c1c1e
    static let panelBg = Color(white: 1.0, opacity: 0.06)
    /// Header 分割线
    static let headerBorder = Color(white: 1.0, opacity: 0.06)
    /// 搜索栏背景
    static let searchBg = Color(white: 1.0, opacity: 0.03)
    /// 选中行背景
    static let selectedBg = Color(red: 0.290, green: 0.620, blue: 0.969, opacity: 0.06)
    /// Hover 行背景
    static let hoverBg = Color(white: 1.0, opacity: 0.04)

    // MARK: 兼容别名

    static let background = Color(nsColor: .controlBackgroundColor)
    static let surface = Color(white: 1.0, opacity: 0.04)
    static let border = Color(white: 1.0, opacity: 0.08)
    static let borderSubtle = Color(white: 1.0, opacity: 0.04)
    static let pinnedHighlight = accent.opacity(0.06)
    static let primary = accent
    static let primaryLight = accent.opacity(0.12)
    static let primaryDark = Color(red: 0.220, green: 0.530, blue: 0.880)
    static let secondaryBackground = surface
    static let separator = Color(white: 1.0, opacity: 0.06)

    // MARK: NSColor（AppKit 桥接）

    static let nsAccent = NSColor(red: 0.290, green: 0.620, blue: 0.969, alpha: 1.0)
    static let nsAccentLight = nsAccent.withAlphaComponent(0.12)
    static let nsAccentDark = NSColor(red: 0.220, green: 0.530, blue: 0.880, alpha: 1.0)
    static let nsPrimary = nsAccent
    static let nsPrimaryLight = nsAccentLight
    static let nsPrimaryDark = nsAccentDark
}

// MARK: - 间距

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

// MARK: - 圆角

enum OneBoardRadius {
    /// 按钮（匹配 HTML .btn border-radius:6px）
    static let sm: CGFloat = 6
    /// 面板（用户选择 md=8pt，HTML 实际 10pt → 折中 8pt）
    static let md: CGFloat = 8
    /// 大面板
    static let lg: CGFloat = 14
    /// 旧版兼容
    static let xl: CGFloat = 8
    static let twoXL: CGFloat = 14
    static let pill: CGFloat = 6
}

// MARK: - 阴影

enum OneBoardShadow {
    static let sm = (color: Color.black.opacity(0.15), radius: CGFloat(4), y: CGFloat(2))
    static let md = (color: Color.black.opacity(0.20), radius: CGFloat(8), y: CGFloat(3))
    static let lg = (color: Color.black.opacity(0.25), radius: CGFloat(16), y: CGFloat(6))
}

// MARK: - 字体

enum OneBoardFont {
    static let title = Font.system(size: 14, weight: .semibold)        // HTML .panel-header 13px→14pt
    static let headline = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)          // HTML body
    static let callout = Font.system(size: 12, weight: .medium)        // HTML .panel-row 12px
    static let caption = Font.system(size: 11, weight: .regular)       // HTML 辅助
    static let captionSmall = Font.system(size: 10, weight: .regular)  // HTML .time 10px
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let titleLarge = Font.system(size: 20, weight: .bold, design: .serif)
    static let monoBody = mono
    static let monoCaption = Font.system(size: 10, weight: .regular, design: .monospaced)
}
