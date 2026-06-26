import SwiftUI

// MARK: - OneBoard 统一组件库

// MARK: 主操作按钮

struct OneBoardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, OneBoardSpacing.lg)
            .padding(.vertical, OneBoardSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                    .fill(OneBoardColors.accent)
                    .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1.0 : 0.5))
            )
            .foregroundColor(.white)
    }
}

// MARK: 次级按钮

struct OneBoardSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, OneBoardSpacing.lg)
            .padding(.vertical, OneBoardSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                    .fill(OneBoardColors.accent.opacity(configuration.isPressed ? 0.15 : 0.10))
            )
            .foregroundColor(OneBoardColors.accent)
    }
}

// MARK: 图标按钮（工具栏小按钮）

struct OneBoardIconButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .fill(isSelected
                        ? OneBoardColors.accent
                        : (configuration.isPressed ? OneBoardColors.accent.opacity(0.15) : Color.clear))
            )
            .foregroundColor(isSelected ? .white : OneBoardColors.textSecondary)
            .font(.system(size: 14))
    }
}

// MARK: 面板容器

struct OneBoardPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
            .shadow(
                color: OneBoardShadow.lg.color,
                radius: OneBoardShadow.lg.radius,
                x: 0,
                y: OneBoardShadow.lg.y
            )
    }
}

// MARK: 面板 Header

struct OneBoardPanelHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OneBoardSpacing.lg)
            .padding(.vertical, OneBoardSpacing.sm)
            .background(OneBoardColors.surface.opacity(0.5))
            .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: 列表行

struct OneBoardListRowModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OneBoardSpacing.sm)
            .padding(.vertical, OneBoardSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .fill(isHovered ? OneBoardColors.accent.opacity(0.08) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: 卡片

struct OneBoardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(OneBoardSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                    .fill(OneBoardColors.background)
                    .shadow(
                        color: OneBoardShadow.sm.color,
                        radius: OneBoardShadow.sm.radius,
                        x: 0,
                        y: OneBoardShadow.sm.y
                    )
            )
    }
}

// MARK: 输入框

struct OneBoardTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(OneBoardSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                    .fill(OneBoardColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                            .stroke(OneBoardColors.borderSubtle, lineWidth: 1)
                    )
            )
    }
}

// MARK: - 统一关闭按钮（所有面板一致）

/// 统一关闭按钮样式：28×28pt，xmark 图标，右上角位置
struct OneBoardCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundColor(OneBoardColors.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: OneBoardRadius.md)
                        .fill(Color.clear)
                )
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 统一置顶按钮

/// 统一置顶按钮样式（有置顶功能的面板使用）
struct OneBoardPinButton: View {
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundColor(isPinned ? OneBoardColors.accent : OneBoardColors.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: OneBoardRadius.md)
                        .fill(isPinned ? OneBoardColors.accent.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - View 扩展

extension View {
    /// 主操作按钮样式
    func oneBoardPrimaryButton() -> some View {
        buttonStyle(OneBoardPrimaryButtonStyle())
    }

    /// 次级按钮样式
    func oneBoardSecondaryButton() -> some View {
        buttonStyle(OneBoardSecondaryButtonStyle())
    }

    /// 图标按钮样式
    func oneBoardIconButton(isSelected: Bool = false) -> some View {
        buttonStyle(OneBoardIconButtonStyle(isSelected: isSelected))
    }

    /// 统一面板样式
    func oneBoardPanel() -> some View {
        modifier(OneBoardPanelModifier())
    }

    /// 面板 header 样式
    func oneBoardPanelHeader() -> some View {
        modifier(OneBoardPanelHeaderModifier())
    }

    /// 列表行样式
    func oneBoardListRow() -> some View {
        modifier(OneBoardListRowModifier())
    }

    /// 卡片样式
    func oneBoardCard() -> some View {
        modifier(OneBoardCardModifier())
    }

    /// 输入框样式
    func oneBoardTextField() -> some View {
        modifier(OneBoardTextFieldStyle())
    }
}
