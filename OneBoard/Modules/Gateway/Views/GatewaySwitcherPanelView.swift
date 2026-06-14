import SwiftUI

struct GatewaySwitcherPanelView: View {
    @StateObject private var viewModel = GatewayViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.displayGateway)
                        .font(.headline)
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
                    .disabled(viewModel.isRefreshing)
                    .help("刷新")

                    Button {
                        MenuBarManager.shared.closeGatewaySwitcherPanel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("关闭")
                }
            }

            if !viewModel.snapshot.dnsServers.isEmpty {
                Text("DNS \(viewModel.snapshot.dnsServers.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            ForEach(viewModel.profiles) { profile in
                Button {
                    viewModel.switchGateway(to: profile)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: profile.symbolName)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.title)
                            Text(summary(for: profile))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.activeProfile?.id == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSwitching || viewModel.activeProfile?.id == profile.id)
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
                .help("网关设置")
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { viewModel.refresh() }
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
