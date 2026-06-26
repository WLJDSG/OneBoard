import SwiftUI
import AppKit

// MARK: - OneBoard 统一设计令牌系统 v2.0

/// 品牌色 / 语义色 / 间距 / 圆角 / 阴影 / 字体 统一设计令牌
enum OneBoardColors {

    // MARK: 品牌色

    /// 主色调（操作按钮、选中态、焦点环）
    /// 苹果风格蓝，比旧版 #59A6F2 更鲜艳
    static let accent = Color(red: 0.29, green: 0.62, blue: 0.97)

    /// 浅色变体（hover 背景、次要强调）
    static let accentLight = Color(red: 0.48, green: 0.75, blue: 1.0)

    /// 深色变体
    static let accentDark = Color(red: 0.20, green: 0.52, blue: 0.85)

    // MARK: 语义色

    /// 成功状态
    static let success = Color(nsColor: .systemGreen)

    /// 警告状态
    static let warning = Color(nsColor: .systemOrange)

    /// 错误 / 删除
    static let destructive = Color(nsColor: .systemRed)

    /// 置顶条目背景
    static let pinnedHighlight = Color(red: 1.0, green: 0.91, blue: 0.69)

    // MARK: 中性色（系统自适应 → 自动支持深色模式）

    /// 主要文字
    static let textPrimary = Color(nsColor: .labelColor)

    /// 次要文字 / 描述
    static let textSecondary = Color(nsColor: .secondaryLabelColor)

    /// 占位符 / 禁用态文字
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    /// 内容区背景
    static let background = Color(nsColor: .controlBackgroundColor)

    /// 分割线 / 边框
    static let border = Color(nsColor: .separatorColor)

    /// 细微边框
    static let borderSubtle = Color(nsColor: .separatorColor).opacity(0.5)

    // MARK: 旧版兼容别名（逐步迁移后删除）

    static let primary = accent
    static let primaryLight = accentLight
    static let primaryDark = accentDark

    // MARK: NSColor 版本（AppKit 桥接用）

    static let nsAccent = NSColor(red: 0.29, green: 0.62, blue: 0.97, alpha: 1.0)
    static let nsAccentLight = NSColor(red: 0.48, green: 0.75, blue: 1.0, alpha: 1.0)
    static let nsAccentDark = NSColor(red: 0.20, green: 0.52, blue: 0.85, alpha: 1.0)

    // 旧版 NSColor 别名
    static let nsPrimary = nsAccent
    static let nsPrimaryLight = nsAccentLight
    static let nsPrimaryDark = nsAccentDark
}

// MARK: - 间距系统（4pt 网格）

enum OneBoardSpacing {
    /// 4pt — 图标与文字间距
    static let twoXS: CGFloat = 4
    /// 8pt — 行内间距、小型按钮内边距
    static let xs: CGFloat = 8
    /// 12pt — 卡片内边距、列表行内边距
    static let sm: CGFloat = 12
    /// 16pt — 区块内边距、按钮水平内边距
    static let md: CGFloat = 16
    /// 20pt — 区块间距
    static let lg: CGFloat = 20
    /// 24pt — 面板内边距
    static let xl: CGFloat = 24
    /// 32pt — 页面级间距
    static let twoXL: CGFloat = 32
}

// MARK: - 圆角系统

enum OneBoardRadius {
    /// 4pt — 小图标容器、标签、徽章
    static let sm: CGFloat = 4
    /// 6pt — 列表行、按钮
    static let md: CGFloat = 6
    /// 8pt — 卡片、输入框
    static let lg: CGFloat = 8
    /// 12pt — 浮动面板、弹出窗口
    static let xl: CGFloat = 12
    /// 16pt — 大型模态面板
    static let twoXL: CGFloat = 16
}

// MARK: - 阴影系统

enum OneBoardShadow {
    /// 小阴影 — 卡片、行 hover
    static let sm: (color: Color, radius: CGFloat, y: CGFloat) =
        (Color.black.opacity(0.06), 4, 1)

    /// 中阴影 — 小浮动面板
    static let md: (color: Color, radius: CGFloat, y: CGFloat) =
        (Color.black.opacity(0.08), 8, 2)

    /// 大阴影 — 大浮动面板
    static let lg: (color: Color, radius: CGFloat, y: CGFloat) =
        (Color.black.opacity(0.12), 16, 4)
}

// MARK: - 字体排版系统

enum OneBoardFont {
    /// 面板标题 — 22pt bold
    static let titleLarge: Font = .system(size: 22, weight: .bold)
    /// 区块标题 — 17pt semibold
    static let title: Font = .system(size: 17, weight: .semibold)
    /// 列表项标题 — 14pt semibold
    static let headline: Font = .system(size: 14, weight: .semibold)
    /// 正文 — 13pt regular
    static let body: Font = .system(size: 13, weight: .regular)
    /// 标签 / 状态 — 12pt medium
    static let callout: Font = .system(size: 12, weight: .medium)
    /// 辅助信息 — 11pt regular
    static let caption: Font = .system(size: 11, weight: .regular)
    /// 小标签 — 10pt regular
    static let captionSmall: Font = .system(size: 10, weight: .regular)

    // 等宽字体
    /// OCR 文字 — 13pt mono
    static let monoBody: Font = .system(size: 13, weight: .regular, design: .monospaced)
    /// 尺寸标签 — 11pt mono
    static let monoCaption: Font = .system(size: 11, weight: .regular, design: .monospaced)
}
