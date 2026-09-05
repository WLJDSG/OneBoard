import SwiftUI

/// 设置窗口独立视觉令牌，避免影响截图画布和悬浮工具栏。
enum SettingsPalette {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.52, green: 0.64, blue: 1, alpha: 1)
            : NSColor(red: 0.22, green: 0.36, blue: 0.88, alpha: 1)
    })
    static let teal = Color(red: 0.05, green: 0.62, blue: 0.65)
    static let ink = Color.primary
    static let muted = Color.secondary
}

struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [SettingsPalette.accent.opacity(scheme == .dark ? 0.12 : 0.075),
                                    .clear, SettingsPalette.teal.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color(nsColor: .controlBackgroundColor) : .white,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.08 : 0.025), radius: 12, y: 5)
    }
}

/// 使用 Section 的公开子视图 API 保留现有控件及绑定，只调整排版。
struct SettingsForm<Content: View>: View {
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
                                        .padding(.vertical, 17)
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
            .padding(.horizontal, 28)
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
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : SettingsPalette.ink)
            .background(prominent ? SettingsPalette.accent : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct SettingsNavigationItem: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
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
