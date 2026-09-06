import SwiftUI

struct MacStatusSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.macStatusShowInMenuBar) private var showInMenuBar = true
    @AppStorage("macStatus.menuMode") private var mode = "network"
    var body: some View {
        SettingsForm {
            Section {
                Toggle("在菜单栏显示 Mac 状态", isOn: $showInMenuBar)
                Picker("菜单栏显示", selection: $mode) {
                    Text("上传 / 下载速度").tag("network")
                    Text("CPU 使用率").tag("cpu")
                    Text("内存使用率").tag("memory")
                }
            } header: { Text("Mac 状态") } footer: {
                Text("停留 0.7 秒展示卡片；点击可立即打开或关闭。实时指标每秒更新。")
            }
        }
        .onAppear { if mode == "icon" { mode = "network" } }
        .onChange(of: showInMenuBar) { _, _ in MenuBarManager.shared.updateMacStatusItemVisibility() }
    }
}
