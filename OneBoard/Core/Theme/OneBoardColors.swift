import SwiftUI
import AppKit

// MARK: - OneBoard 通用设计令牌

/// 兼容既有组件的语义入口，与设置及工具面板共用自适应颜色。
enum OneBoardColors {

    // MARK: 自适应强调色

    static let accent = SettingsPalette.accent
    static let accentLight = accent.opacity(0.08)
    static let accentMedium = accent.opacity(0.15)

    // MARK: 语义色

    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)

    // MARK: 自适应文本色

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary

    // MARK: 背景色

    /// 面板底色
    static let panelBg = SettingsPalette.canvas
    /// 搜索栏/Hover 背景
    static let hoverBg = SettingsPalette.hover
    /// 选中行背景
    static let selectedBg = accent.opacity(0.06)
    /// Header 底
    static let headerBg = SettingsPalette.canvas

    // MARK: 边框

    /// 面板边框
    static let panelBorder = SettingsPalette.border
    /// 分割线
    static let divider = SettingsPalette.border
    /// Header 底线
    static let headerBorder = divider
    /// 搜索栏背景
    static let searchBg = SettingsPalette.surface

    // MARK: 内容区颜色

    static let background = Color(nsColor: .controlBackgroundColor)
    static let surface = hoverBg
    static let border = divider
    static let borderSubtle = Color.primary.opacity(0.05)
    static let pinnedHighlight = accent.opacity(0.04)

    // MARK: NSColor

    static let nsAccent = NSColor(SettingsPalette.accent)
    static let nsAccentLight = nsAccent.withAlphaComponent(0.08)
    static let nsAccentDark = nsAccent
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

// MARK: - 紧凑内容圆角

enum OneBoardRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 10
    static let twoXL: CGFloat = 14
    static let pill: CGFloat = 8
}

// MARK: - 浮层阴影

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
    static let captionSmall = Font.system(size: 11, weight: .regular)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let titleLarge = Font.system(size: 20, weight: .semibold)
    static let monoBody = mono
    static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
}
