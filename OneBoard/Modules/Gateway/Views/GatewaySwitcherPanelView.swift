import SwiftUI

enum GatewaySwitcherPanelLayout {
    static let size = CGSize(width: 360, height: 360)
}

/// 网关切换面板 — Apple Notes 风格
struct GatewaySwitcherPanelView: View {
    @StateObject private var viewModel = GatewayViewModel.shared
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OneBoardColors.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("网关切换")
                        .oneBoardFont(.title)
                    if !viewModel.displayGateway.isEmpty {
                        Text(viewModel.displayGateway)
                            .oneBoardFont(.caption)
                            .foregroundColor(OneBoardColors.textSecondary)
                    }
                }
                Spacer()
                Button { viewModel.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(OneBoardColors.textTertiary)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(isAnimating ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isAnimating)
                }
                .buttonStyle(.borderless)
                OneBoardCloseButton { MenuBarManager.shared.closeGatewaySwitcherPanel() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(OneBoardColors.headerBorder).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.profiles) { profile in
                        profileCard(profile)
                    }
                }
                .padding(12)
            }

            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundColor(OneBoardColors.textTertiary)
                Text(dnsSummary)
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    SettingsWindowManager.shared.show(selectedTab: .gateway)
                } label: {
                    Label("管理配置", systemImage: "slider.horizontal.3")
                        .oneBoardFont(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(OneBoardColors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OneBoardColors.hoverBg)
            .overlay(Rectangle().fill(OneBoardColors.headerBorder).frame(height: 1), alignment: .top)
        }
        .frame(width: GatewaySwitcherPanelLayout.size.width, height: GatewaySwitcherPanelLayout.size.height)
        .background(OneBoardColors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
        .shadow(color: OneBoardShadow.lg.color, radius: OneBoardShadow.lg.radius, x: 0, y: OneBoardShadow.lg.y)
        .onAppear {
            viewModel.refresh()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .onChange(of: viewModel.isRefreshing) { _, newValue in
            isAnimating = newValue
        }
    }

    private func profileCard(_ profile: GatewayProfile) -> some View {
        let isActive = viewModel.activeProfile?.id == profile.id
        return Button { viewModel.switchGateway(to: profile) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? OneBoardColors.accent.opacity(0.14) : OneBoardColors.hoverBg)
                        .frame(width: 36, height: 36)
                    Image(systemName: isActive ? "network.badge.shield.half.filled" : "network")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isActive ? OneBoardColors.accent : OneBoardColors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.title)
                        .oneBoardFont(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(OneBoardColors.textPrimary)
                    Text(summary(for: profile))
                        .oneBoardFont(.caption)
                        .foregroundColor(OneBoardColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if viewModel.isSwitching && !isActive {
                    ProgressView().controlSize(.small)
                } else if isActive {
                    Label("当前", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(OneBoardColors.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(OneBoardColors.textTertiary)
                }
            }
            .padding(11)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                    .fill(isActive ? OneBoardColors.selectedBg : OneBoardColors.panelBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                    .stroke(isActive ? OneBoardColors.accent.opacity(0.35) : OneBoardColors.panelBorder, lineWidth: 1)
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
