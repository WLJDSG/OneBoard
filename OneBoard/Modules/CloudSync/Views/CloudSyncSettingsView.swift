import SwiftUI

struct CloudSyncSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.iCloudSyncEnabled) private var enabled = false
    @StateObject private var viewModel = CloudSyncViewModel.shared
    @State private var confirmRestore = false

    var body: some View {
        SettingsForm {
            Section {
                Toggle("自动备份 OneBoard 配置到 iCloud", isOn: Binding(get: { enabled }, set: { viewModel.setEnabled($0) }))
                Text("先在授权页选择 iCloud Drive，开启后自动创建 app/oneboard，配置变更会自动备份；重装后可恢复已有备份。")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("备份位置", value: "iCloud Drive / app / oneboard")
                Text(viewModel.statusMessage).font(.callout).foregroundStyle(.secondary)
                if let date = viewModel.lastSync { Text("最近备份：\(date.formatted())").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("立即备份") { viewModel.syncNow() }.disabled(!enabled || viewModel.isSyncing)
                    Button("从备份恢复") { confirmRestore = true }.disabled(viewModel.isSyncing)
                    Button("管理文件访问") { SettingsWindowManager.shared.show(selectedTab: .authorization) }
                    Button("打开备份文件夹") { viewModel.revealBackup() }
                }
            } header: { Text("iCloud 配置备份") }
        }
        .confirmationDialog("用 iCloud 备份恢复配置？当前对应配置将被替换。", isPresented: $confirmRestore) {
            Button("恢复配置") { viewModel.restoreBackup() }
        }
        .onAppear { viewModel.startIfEnabled() }
    }
}
