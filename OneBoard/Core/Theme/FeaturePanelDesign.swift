import SwiftUI

/// 所有工具外壳共享中性底色、强调色和控件尺寸。
enum FeaturePalette {
    static let accent = SettingsPalette.accent
    static let text = Color.primary
    static let secondary = Color.secondary
    static let surface = SettingsPalette.surface
    static let border = SettingsPalette.border
    static let hover = SettingsPalette.hover
}

enum InterfaceMotion {
    static let feedback = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.15)
    static let revealDuration: TimeInterval = 0.3
    static let dismissDuration: TimeInterval = 0.2

    static func panelDuration(presenting: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : (presenting ? revealDuration : dismissDuration)
    }
}

struct FeaturePanelHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(FeaturePalette.accent)
                .frame(width: 24, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(InterfaceMetrics.panelInset)
    }
}

struct FeaturePanelIconButton: View {
    let icon: String
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: InterfaceMetrics.controlHeight, height: InterfaceMetrics.controlHeight)
        }
        .buttonStyle(FeatureSelectionStyle(selected: selected, horizontalPadding: 0))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 筛选、分段选项和图标按钮使用同一组反馈，点击与键盘动作即时生效。
struct FeatureSelectionStyle: ButtonStyle {
    let selected: Bool
    var horizontalPadding: CGFloat = 10
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Selection(configuration: configuration, selected: selected, horizontalPadding: horizontalPadding, enabled: enabled)
    }

    private struct Selection: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let horizontalPadding: CGFloat
        let enabled: Bool
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: InterfaceMetrics.controlHeight)
                .foregroundStyle(selected ? FeaturePalette.accent : FeaturePalette.text)
                .background(selected ? FeaturePalette.accent.opacity(0.12) : hovered && enabled ? FeaturePalette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius)
                    .strokeBorder(selected ? FeaturePalette.accent.opacity(0.24) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius))
                .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
                .animation(reduceMotion ? nil : InterfaceMotion.feedback, value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct FeatureEmptyState: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .regular))
                .foregroundStyle(FeaturePalette.accent)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

private struct FeatureCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FeaturePalette.surface, in: RoundedRectangle(cornerRadius: InterfaceMetrics.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: InterfaceMetrics.cardRadius).strokeBorder(FeaturePalette.border))
    }
}

struct FeaturePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(FeaturePalette.text)
            .font(.system(size: 13))
            .tint(FeaturePalette.accent)
            .buttonStyle(SettingsActionStyle())
            .background(SettingsBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: InterfaceMetrics.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: InterfaceMetrics.panelRadius).strokeBorder(FeaturePalette.border))
    }
}

extension View {
    func featurePanelStyle() -> some View { modifier(FeaturePanelModifier()) }
    func featureCardStyle() -> some View { modifier(FeatureCardModifier()) }
}
