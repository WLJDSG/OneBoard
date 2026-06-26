import SwiftUI

// MARK: - 统一按钮 / 列表 / 卡片修饰符
// 注意：新版组件在 ComponentLibrary.swift 中，此文件保留旧版兼容别名

// MARK: 主按钮（兼容别名 → 新组件）

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(OneBoardColors.accent).opacity(configuration.isPressed ? 0.8 : 1.0))
            .foregroundColor(.white)
    }
}

struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content.background(isHovered ? OneBoardColors.hoverBg : Color.clear)
            .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
    }
}

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(OneBoardSpacing.sm).background(RoundedRectangle(cornerRadius: OneBoardRadius.md).fill(OneBoardColors.surface))
    }
}

struct OneBoardPanelStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(OneBoardColors.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OneBoardRadius.md).stroke(OneBoardColors.headerBorder, lineWidth: 1))
            .shadow(color: OneBoardShadow.lg.color, radius: OneBoardShadow.lg.radius, x: 0, y: OneBoardShadow.lg.y)
    }
}

// MARK: - View 扩展（兼容别名）

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

    /// 面板样式
    func oneBoardPanelStyle() -> some View {
        self.modifier(OneBoardPanelStyleModifier())
    }
}
