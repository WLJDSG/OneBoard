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
                RoundedRectangle(cornerRadius: 10)
                    .fill(OneBoardColors.background)
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
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
}