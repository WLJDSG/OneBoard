import SwiftUI

struct GatewaySettingsView: View {
    @StateObject private var viewModel = GatewayViewModel.shared
    @State private var editingProfile: GatewayProfile?
    @State private var isAddingProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section {
                    LabeledContent("当前网关", value: viewModel.displayGateway)
                    LabeledContent("网络服务", value: viewModel.displayService.isEmpty ? "未检测到" : viewModel.displayService)
                    LabeledContent("接口", value: viewModel.snapshot.interfaceName ?? "未知")
                    LabeledContent("DNS", value: viewModel.snapshot.dnsServers.isEmpty ? "未设置" : viewModel.snapshot.dnsServers.joined(separator: ", "))
                    Button("刷新网络状态") { viewModel.refresh() }
                        .disabled(viewModel.isRefreshing)
                } header: {
                    Text("当前网络")
                }

                Section {
                    ForEach(viewModel.profiles) { profile in
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
                            Button("切换") { viewModel.switchGateway(to: profile) }
                                .disabled(viewModel.isSwitching)
                            Button("编辑") { editingProfile = profile }
                            Button(role: .destructive) {
                                viewModel.deleteProfile(id: profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button {
                        isAddingProfile = true
                    } label: {
                        Label("新增网关", systemImage: "plus")
                    }
                } header: {
                    Text("网关配置")
                }
            }
            .formStyle(.grouped)

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding()
        .sheet(isPresented: $isAddingProfile) {
            GatewayProfileEditorView(
                viewModel: GatewayProfileEditorViewModel(),
                onSave: { profile in
                    viewModel.addProfile(profile)
                    isAddingProfile = false
                },
                onCancel: { isAddingProfile = false }
            )
        }
        .sheet(item: $editingProfile) { profile in
            GatewayProfileEditorView(
                viewModel: GatewayProfileEditorViewModel(profile: profile),
                onSave: { updated in
                    viewModel.updateProfile(updated)
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
        }
    }

    private func summary(for profile: GatewayProfile) -> String {
        switch profile.mode {
        case .gatewayAndDNS:
            return "\(profile.gateway) · DNS \(profile.dnsServers.joined(separator: ", "))"
        case .dnsOnly:
            return "仅 DNS · \(profile.dnsServers.joined(separator: ", "))"
        }
    }
}
