import SwiftUI

struct GatewaySwitcherPanelView: View {
    @StateObject private var viewModel = GatewayViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.snapshot.dnsServers.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .font(.system(size: 10))
                            .foregroundColor(OneBoardColors.textSecondary)
                        Text("DNS \(viewModel.snapshot.dnsServers.joined(separator: ", "))")
                            .oneBoardFont(.caption)
                            .foregroundColor(OneBoardColors.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(OneBoardColors.accent.opacity(0.04))
                    .cornerRadius(8)
                }

                VStack(spacing: 2) {
                    ForEach(viewModel.profiles) { profile in
                        Button {
                            viewModel.switchGateway(to: profile)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: profile.symbolName)
                                    .font(.system(size: 16))
                                    .foregroundColor(OneBoardColors.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.title)
                                        .oneBoardFont(.body)
                                    Text(summary(for: profile))
                                        .oneBoardFont(.caption)
                                        .foregroundColor(OneBoardColors.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if viewModel.activeProfile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(OneBoardColors.success)
                                }
                            }
                            .contentShape(Rectangle())
                            .oneBoardListRow()
                            .background(
                                viewModel.activeProfile?.id == profile.id
                                    ? OneBoardColors.accent.opacity(0.08)
                                    : Color.clear
                            )
                            .overlay(alignment: .leading) {
                                if viewModel.activeProfile?.id == profile.id {
                                    Rectangle()
                                        .fill(OneBoardColors.accent)
                                        .frame(width: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .opacity(viewModel.isSwitching || viewModel.activeProfile?.id == profile.id ? 0.5 : 1.0)
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .oneBoardFont(.caption)
                            .foregroundColor(OneBoardColors.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                HStack {
                    Spacer()
                    Button {
                        SettingsWindowManager.shared.show(selectedTab: .gateway)
                    } label: {
                        Text("管理配置...")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(OneBoardColors.accent)
                    Spacer()
                }
            }
            .padding(OneBoardSpacing.sm)
        }
        .frame(width: 360)
        .oneBoardPanelStyle()
        .onAppear { viewModel.refresh() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "network")
                .oneBoardFont(.headline)
                .foregroundColor(OneBoardColors.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.displayGateway)
                    .oneBoardFont(.headline)
                Text(viewModel.displayService.isEmpty ? "未检测到当前网络服务" : viewModel.displayService)
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(
                            viewModel.isRefreshing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : nil,
                            value: viewModel.isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .help("刷新")

                OneBoardCloseButton {
                    MenuBarManager.shared.closeGatewaySwitcherPanel()
                }
            }
        }
        .oneBoardPanelHeader()
    }

    private func summary(for profile: GatewayProfile) -> String {
        switch profile.mode {
        case .gatewayAndDNS:
            return "\(profile.gateway) · \(profile.dnsServers.joined(separator: ", "))"
        case .dnsOnly:
            return "仅 DNS · \(profile.dnsServers.joined(separator: ", "))"
        }
    }
}
