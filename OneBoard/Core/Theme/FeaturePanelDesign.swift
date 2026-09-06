import SwiftUI

/// 独立操作面板复用设置页视觉，不修改截图遮罩及标注工具栏。
enum FeaturePalette {
    static let accent = SettingsPalette.accent
    static let text = Color.primary
    static let secondary = Color.secondary
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.07)
    static let hover = Color.primary.opacity(0.04)
}

struct FeaturePanelHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FeaturePalette.accent)
                .frame(width: 38, height: 38)
                .background(FeaturePalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(16)
    }
}

struct FeaturePanelIconButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(FeaturePalette.hover, in: RoundedRectangle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
    }
}

struct FeaturePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(FeaturePalette.text)
            .tint(FeaturePalette.accent)
            .background(SettingsBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(FeaturePalette.border))
    }
}

extension View {
    func featurePanelStyle() -> some View { modifier(FeaturePanelModifier()) }
}
