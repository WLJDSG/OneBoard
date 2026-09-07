import SwiftUI

/// 设置与工具外壳共用视觉令牌，不参与截图原图或标注颜色。
enum SettingsPalette {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.52, green: 0.64, blue: 1, alpha: 1)
            : NSColor(red: 0.22, green: 0.36, blue: 0.88, alpha: 1)
    })
    static let teal = Color(nsColor: .systemTeal)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.105, alpha: 1) : NSColor(white: 0.96, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.145, alpha: 1) : .white
    })
    static let border = Color.primary.opacity(0.09)
    static let hover = Color.primary.opacity(0.055)
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })
}

enum InterfaceMetrics {
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let controlHeight: CGFloat = 30
    static let panelInset: CGFloat = 16
    static let pageInset: CGFloat = 28
}

struct SettingsBackdrop: View {
    var body: some View {
        SettingsPalette.canvas.ignoresSafeArea()
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .featureCardStyle()
    }
}

/// 使用 Section 的公开子视图 API 保留现有控件及绑定，只调整排版。
struct SettingsForm<Content: View>: View {
    var inset: CGFloat = InterfaceMetrics.pageInset
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sections: content) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        if !section.header.isEmpty {
                            VStack(alignment: .leading, spacing: 6) { ForEach(section.header) { $0 } }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                        SettingsCard {
                            VStack(spacing: 0) {
                                ForEach(section.content) { row in
                                    if row.id != section.content.first?.id {
                                        Divider().opacity(0.45).padding(.horizontal, 20)
                                    }
                                    row
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 14)
                                }
                            }
                        }
                        if !section.footer.isEmpty {
                            VStack(alignment: .leading, spacing: 4) { ForEach(section.footer) { $0 } }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, inset)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .labeledContentStyle(SettingsFieldStyle())
        .toggleStyle(SettingsToggleStyle())
        .controlSize(.regular)
        .tint(SettingsPalette.accent)
        .buttonStyle(SettingsActionStyle())
    }
}

struct SettingsActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Action(configuration: configuration, prominent: prominent, enabled: enabled)
    }

    private struct Action: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let enabled: Bool
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(minHeight: InterfaceMetrics.controlHeight)
                .foregroundStyle(prominent ? SettingsPalette.onAccent : SettingsPalette.ink)
                .background(prominent ? SettingsPalette.accent : SettingsPalette.hover,
                            in: RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius)
                    .strokeBorder(hovered && enabled ? SettingsPalette.accent.opacity(0.45) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius))
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .animation(reduceMotion ? nil : InterfaceMotion.feedback, value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct SettingsNavigationItem: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if selected {
                    Circle().fill(SettingsPalette.accent).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(selected ? SettingsPalette.accent : .secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(selected ? SettingsPalette.accent.opacity(0.1) : Color.primary.opacity(hovered ? 0.04 : 0),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : InterfaceMotion.feedback, value: hovered)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsEditorGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            SettingsCard { configuration.content.padding(18) }
        }
    }
}


struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingsFieldStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 24) {
            configuration.label.font(.system(size: 13, weight: .medium))
            Spacer(minLength: 20)
            configuration.content.foregroundStyle(.secondary)
        }
    }
}
