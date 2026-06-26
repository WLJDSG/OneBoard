import SwiftUI

// MARK: - 淡蓝色主题按钮样式

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(OneBoardColors.primary)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(.white)
            .font(.system(size: 13, weight: .medium))
    }
}

// MARK: - 列表行悬停效果

struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? OneBoardColors.primary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - 卡片样式

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(OneBoardColors.background)
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
    }
}

// MARK: - 面板样式

struct OneBoardPanelStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
    }
}

struct OneBoardPanelHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
            .overlay(Divider(), alignment: .bottom)
    }
}

struct OneBoardListRowModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - View 扩展

extension View {
    /// 淡蓝色主题按钮样式
    func primaryButtonStyle() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }

    /// 列表行悬停高亮效果
    func hoverEffect() -> some View {
        self.modifier(HoverEffectModifier())
    }

    /// 卡片样式
    func cardStyle() -> some View {
        self.modifier(CardStyleModifier())
    }

    func oneBoardPanelStyle() -> some View {
        self.modifier(OneBoardPanelStyleModifier())
    }

    func oneBoardPanelHeader() -> some View {
        self.modifier(OneBoardPanelHeaderModifier())
    }

    func oneBoardListRow() -> some View {
        self.modifier(OneBoardListRowModifier())
    }
}
