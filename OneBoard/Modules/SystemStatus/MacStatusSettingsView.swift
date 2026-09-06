import SwiftUI

struct MacStatusSettingsView: View {
    @AppStorage("macStatus.menuMode") private var mode = "icon"
    @AppStorage("macStatus.menuIcon") private var icon = "gauge.with.dots.needle.50percent"
    var body: some View {
        SettingsForm {
            Section {
                Picker("菜单栏显示", selection: $mode) {
                    Text("图标").tag("icon")
                    Text("上传 / 下载速度").tag("network")
                    Text("CPU 使用率").tag("cpu")
                    Text("内存使用率").tag("memory")
                }
                if mode == "icon" {
                    Picker("图标样式", selection: $icon) {
                        Label("仪表盘", systemImage: "gauge.with.dots.needle.50percent").tag("gauge.with.dots.needle.50percent")
                        Label("电脑", systemImage: "desktopcomputer").tag("desktopcomputer")
                        Label("芯片", systemImage: "cpu").tag("cpu")
                        Label("波形", systemImage: "waveform.path.ecg").tag("waveform.path.ecg")
                    }
                }
            } header: { Text("Mac 状态") } footer: {
                Text("停留 0.7 秒展示卡片；点击可立即打开或关闭。实时指标每秒更新。")
            }
        }
    }
}
