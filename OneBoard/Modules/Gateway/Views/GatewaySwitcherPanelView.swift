import SwiftUI

struct GatewaySwitcherPanelView: View {
    @StateObject private var viewModel = GatewayViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.snapshot.dnsServers.isEmpty {
                    Text("DNS \(viewModel.snapshot.dnsServers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                VStack(spacing: 2) {
                    ForEach(viewModel.profiles) { profile in
                        Button {
                            viewModel.switchGateway(to: profile)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: profile.symbolName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(summary(for: profile))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if viewModel.activeProfile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .oneBoardListRow()
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSwitching || viewModel.activeProfile?.id == profile.id)
                    }
                }

                Divider()

                HStack {
                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        SettingsWindowManager.shared.show(selectedTab: .gateway)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("网关设置")
                }
            }
            .padding(14)
        }
        .frame(width: 360)
        .oneBoardPanelStyle()
        .onAppear { viewModel.refresh() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.displayGateway)
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.displayService.isEmpty ? "未检测到当前网络服务" : viewModel.displayService)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isRefreshing)
                .help("刷新")

                Button {
                    MenuBarManager.shared.closeGatewaySwitcherPanel()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
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
