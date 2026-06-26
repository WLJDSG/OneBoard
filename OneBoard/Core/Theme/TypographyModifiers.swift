import SwiftUI

// MARK: - 字体排版 ViewModifier

/// 统一字体修饰符 — 替代散布在各处的 .font(.system(size:...))
/// 用法：Text("标题").oneBoardFont(.title)

enum OneBoardTextStyle {
    case titleLarge
    case title
    case headline
    case body
    case callout
    case caption
    case captionSmall
    case monoBody
    case monoCaption

    var font: Font {
        switch self {
        case .titleLarge: return OneBoardFont.titleLarge
        case .title: return OneBoardFont.title
        case .headline: return OneBoardFont.headline
        case .body: return OneBoardFont.body
        case .callout: return OneBoardFont.callout
        case .caption: return OneBoardFont.caption
        case .captionSmall: return OneBoardFont.captionSmall
        case .monoBody: return OneBoardFont.monoBody
        case .monoCaption: return OneBoardFont.monoCaption
        }
    }
}

struct OneBoardTextStyleModifier: ViewModifier {
    let style: OneBoardTextStyle

    func body(content: Content) -> some View {
        content.font(style.font)
    }
}

extension View {
    /// 应用统一字体样式
    func oneBoardFont(_ style: OneBoardTextStyle) -> some View {
        modifier(OneBoardTextStyleModifier(style: style))
    }
}
