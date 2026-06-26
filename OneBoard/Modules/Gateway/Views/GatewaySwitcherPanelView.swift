import SwiftUI

/// 网关切换面板 — Apple Notes 风格
struct GatewaySwitcherPanelView: View {
    @StateObject private var viewModel = GatewayViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OneBoardColors.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("网关切换")
                        .font(.system(size: 15, weight: .semibold))
                    if !viewModel.displayGateway.isEmpty {
                        Text(viewModel.displayGateway)
                            .font(.system(size: 11))
                            .foregroundColor(OneBoardColors.textSecondary)
                    }
                }
                Spacer()
                Button { viewModel.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(OneBoardColors.textTertiary)
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(viewModel.isRefreshing ? .linear(duration:1).repeatForever(autoreverses:false) : nil, value: viewModel.isRefreshing)
                }
                .buttonStyle(.borderless)
                OneBoardCloseButton { MenuBarManager.shared.closeGatewaySwitcherPanel() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(OneBoardColors.headerBorder).frame(height: 1), alignment: .bottom)

            // Profiles
            VStack(spacing: 1) {
                ForEach(viewModel.profiles) { profile in
                    let isActive = viewModel.activeProfile?.id == profile.id
                    let isDisabled = viewModel.isSwitching || isActive

                    Button { viewModel.switchGateway(to: profile) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isActive ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                                .font(.system(size: 16))
                                .foregroundColor(isActive ? OneBoardColors.accent : OneBoardColors.textTertiary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OneBoardColors.textPrimary)
                                Text(summary(for: profile))
                                    .font(.system(size: 11))
                                    .foregroundColor(OneBoardColors.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isActive {
                                Text("当前")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(OneBoardColors.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .background(isActive ? OneBoardColors.selectedBg : Color.clear)
                        .overlay(alignment: .leading) {
                            if isActive {
                                Rectangle().fill(OneBoardColors.accent).frame(width: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(isDisabled ? 0.5 : 1.0)
                }
            }
            .padding(.vertical, 4)

            // DNS callout
            if !viewModel.snapshot.dnsServers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(OneBoardColors.textTertiary)
                    Text("DNS: \(viewModel.snapshot.dnsServers.joined(separator: ", "))")
                        .font(.system(size: 10))
                        .foregroundColor(OneBoardColors.textSecondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            // Manage button
            HStack {
                Spacer()
                Button {
                    SettingsWindowManager.shared.show(selectedTab: .gateway)
                } label: {
                    Text("管理配置...")
                        .font(.system(size: 12))
                        .foregroundColor(OneBoardColors.accent)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 330)
        .oneBoardPanelStyle()
        .onAppear { viewModel.refresh() }
    }

    private func summary(for profile: GatewayProfile) -> String {
        let parts: [String] = [profile.gateway]
        if !profile.dnsServers.isEmpty {
            return (parts + [profile.dnsServers.joined(separator: ", ")]).joined(separator: " · ")
        }
        return parts.joined(separator: " · ")
    }
}
