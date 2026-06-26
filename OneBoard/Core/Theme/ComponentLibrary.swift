import SwiftUI

// MARK: - OneBoard 统一组件库 — 精确匹配 HTML 设计

// MARK: 主按钮 — HTML .btn-primary: padding:6px 14px, border-radius:6px, fs:12px weight:500

struct OneBoardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
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
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                    .fill(OneBoardColors.accentLight)
            )
            .foregroundColor(OneBoardColors.accent)
    }
}

// MARK: 面板容器 — HTML .panel: bg rgba(255,255,255,.06), border-radius:10px

struct OneBoardPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(OneBoardColors.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .stroke(OneBoardColors.headerBorder, lineWidth: 1)
            )
            .shadow(
                color: OneBoardShadow.lg.color,
                radius: OneBoardShadow.lg.radius,
                x: 0,
                y: OneBoardShadow.lg.y
            )
    }
}

// MARK: 面板 Header — HTML .panel-header: padding:10px 14px, border-bottom

struct OneBoardPanelHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .fill(OneBoardColors.headerBorder)
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

// MARK: 列表行 — HTML .panel-row: padding:8px 14px, gap:10px

struct OneBoardListRowModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovered ? OneBoardColors.hoverBg : Color.clear)
            .onHover { isHovered = $0 }
    }
}

// MARK: 输入框

struct OneBoardTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: OneBoardRadius.md).fill(OneBoardColors.searchBg))
    }
}

// MARK: 统一关闭按钮 — HTML .close: 22x22, border-radius:5px, #8e8e93, fs:11px

struct OneBoardCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundColor(OneBoardColors.textSecondary)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: 统一置顶按钮

struct OneBoardPinButton: View {
    let isPinned: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundColor(isPinned ? OneBoardColors.accent : OneBoardColors.textSecondary)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - View 扩展

extension View {
    func oneBoardPrimaryButton() -> some View { buttonStyle(OneBoardPrimaryButtonStyle()) }
    func oneBoardSecondaryButton() -> some View { buttonStyle(OneBoardSecondaryButtonStyle()) }
    func oneBoardPanel() -> some View { modifier(OneBoardPanelModifier()) }
    func oneBoardPanelHeader() -> some View { modifier(OneBoardPanelHeaderModifier()) }
    func oneBoardListRow() -> some View { modifier(OneBoardListRowModifier()) }
    func oneBoardTextField() -> some View { modifier(OneBoardTextFieldStyle()) }
}
