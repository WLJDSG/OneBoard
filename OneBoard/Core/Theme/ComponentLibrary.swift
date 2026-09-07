import SwiftUI

// MARK: - OneBoard Apple Notes 风格组件库

// MARK: 主按钮

struct OneBoardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(minHeight: InterfaceMetrics.controlHeight)
            .background(RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius).fill(OneBoardColors.accent).opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1.0 : 0.5)))
            .foregroundColor(SettingsPalette.onAccent)
    }
}

// MARK: 次级按钮

struct OneBoardSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(minHeight: InterfaceMetrics.controlHeight)
            .background(RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius).fill(OneBoardColors.accent.opacity(configuration.isPressed ? 0.12 : 0.08)))
            .foregroundColor(OneBoardColors.accent)
    }
}

// MARK: 面板容器 — 暖白底 + 微边框 + 柔阴影

struct OneBoardPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(OneBoardColors.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: OneBoardRadius.lg).stroke(OneBoardColors.panelBorder, lineWidth: 1))
            .shadow(color: OneBoardShadow.lg.color, radius: OneBoardShadow.lg.radius, x: 0, y: OneBoardShadow.lg.y)
    }
}

// MARK: Header 底线

struct OneBoardPanelHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(OneBoardColors.headerBorder).frame(height: 1), alignment: .bottom)
    }
}

// MARK: 列表行

struct OneBoardListRowModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isHovered ? OneBoardColors.hoverBg : Color.clear)
            .onHover { isHovered = $0 }
    }
}

// MARK: 关闭按钮 — Apple Notes 风格 (24×24 圆)

struct OneBoardCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundColor(OneBoardColors.textTertiary)
                .background(Circle().fill(Color.clear))
        }
        .buttonStyle(.borderless)
    }
}

// MARK: 置顶按钮

struct OneBoardPinButton: View {
    let isPinned: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundColor(isPinned ? OneBoardColors.accent : OneBoardColors.textTertiary)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: View 扩展

extension View {
    func oneBoardPrimaryButton() -> some View { buttonStyle(OneBoardPrimaryButtonStyle()) }
    func oneBoardSecondaryButton() -> some View { buttonStyle(OneBoardSecondaryButtonStyle()) }
    func oneBoardPanel() -> some View { modifier(OneBoardPanelModifier()) }
    func oneBoardPanelHeader() -> some View { modifier(OneBoardPanelHeaderModifier()) }
    func oneBoardListRow() -> some View { modifier(OneBoardListRowModifier()) }
}
