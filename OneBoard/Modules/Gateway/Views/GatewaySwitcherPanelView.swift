import SwiftUI

enum GatewaySwitcherPanelLayout {
    static let size = CGSize(width: 380, height: 440)
}

/// 网关切换面板
struct GatewaySwitcherPanelView: View {
    @StateObject private var viewModel = GatewayViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            FeaturePanelHeader(title: "网关切换", subtitle: viewModel.displayGateway.isEmpty ? "查看状态并选择连接配置" : "当前网关 · \(viewModel.displayGateway)", icon: "network") {
                FeaturePanelIconButton(icon: "arrow.clockwise", title: "刷新网络状态") { viewModel.refresh() }
                    .disabled(viewModel.isRefreshing)
                FeaturePanelIconButton(icon: "xmark", title: "关闭") { MenuBarManager.shared.closeGatewaySwitcherPanel() }
            }

            ScrollView {
                VStack(spacing: 12) {
                    if let message = viewModel.statusMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(FeaturePalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            .textSelection(.enabled)
                    }
                    if viewModel.profiles.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "network").font(.system(size: 28)).foregroundStyle(FeaturePalette.accent)
                            Text("尚未添加网关配置").font(.system(size: 13, weight: .medium))
                            Text("在管理配置中添加网关和 DNS，再从这里切换。")
                                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 36)
                    }
                    ForEach(viewModel.profiles) { profile in
                        profileCard(profile)
                    }
                }
                .padding(12)
            }

            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundColor(FeaturePalette.secondary)
                Text(dnsSummary)
                    .oneBoardFont(.caption)
                    .foregroundColor(FeaturePalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    SettingsWindowManager.shared.show(selectedTab: .gateway)
                } label: {
                    Label("管理配置", systemImage: "slider.horizontal.3")
                        .oneBoardFont(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(FeaturePalette.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(FeaturePalette.hover)
            .overlay(Rectangle().fill(FeaturePalette.border).frame(height: 1), alignment: .top)
        }
        .frame(width: GatewaySwitcherPanelLayout.size.width, height: GatewaySwitcherPanelLayout.size.height)
        .featurePanelStyle()
        .onAppear {
            viewModel.refresh()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }

    }

    private func profileCard(_ profile: GatewayProfile) -> some View {
        let isActive = viewModel.activeProfile?.id == profile.id
        return Button { viewModel.switchGateway(to: profile) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? FeaturePalette.accent.opacity(0.14) : FeaturePalette.hover)
                        .frame(width: 36, height: 36)
                    Image(systemName: isActive ? "network.badge.shield.half.filled" : "network")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isActive ? FeaturePalette.accent : FeaturePalette.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.title)
                        .oneBoardFont(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(FeaturePalette.text)
                    Text(summary(for: profile))
                        .oneBoardFont(.caption)
                        .foregroundColor(FeaturePalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if viewModel.isSwitching && !isActive {
                    ProgressView().controlSize(.small)
                } else if isActive {
                    Label("当前", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FeaturePalette.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FeaturePalette.secondary)
                }
            }
            .padding(11)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? FeaturePalette.accent.opacity(0.08) : FeaturePalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? FeaturePalette.accent.opacity(0.35) : FeaturePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSwitching || isActive)
    }

    private var dnsSummary: String {
        guard !viewModel.snapshot.dnsServers.isEmpty else { return "DNS 跟随系统设置" }
        return "DNS  \(viewModel.snapshot.dnsServers.joined(separator: ", "))"
    }

    private func summary(for profile: GatewayProfile) -> String {
        let parts: [String] = [profile.gateway]
        if !profile.dnsServers.isEmpty {
            return (parts + [profile.dnsServers.joined(separator: ", ")]).joined(separator: " · ")
        }
        return parts.joined(separator: " · ")
    }
}
