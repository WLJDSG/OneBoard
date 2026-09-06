import SwiftUI

/// 待办设置页
struct TodoSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.todoRetentionDays) private var retentionDays = -1
    @AppStorage(Constants.UserDefaultsKeys.todoAutoRetractDelay) private var autoRetractDelay = 1.0
    @AppStorage(Constants.UserDefaultsKeys.todoShowNotifications) private var showNotifications = true

    var body: some View {
        SettingsForm {
            // 待办设置
            Section {
                LabeledContent("历史保留天数") {
                    Picker("历史保留天数", selection: $retentionDays) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("永久（默认）").tag(-1)
                }.labelsHidden().frame(width: 230)
                }

                LabeledContent("面板自动收起延迟") {
                    Picker("面板自动收起延迟", selection: Binding(
                    get: { autoRetractDelay },
                    set: { autoRetractDelay = $0 }
                )) {
                    Text("0.5 秒").tag(0.5)
                    Text("1 秒（默认）").tag(1.0)
                    Text("2 秒").tag(2.0)
                }.labelsHidden().frame(width: 230)
                }

                Toggle("到期提醒通知", isOn: Binding(
                    get: { showNotifications },
                    set: { newValue in
                        showNotifications = newValue
                        if newValue {
                            PermissionManager.shared.promptNotificationPermission()
                        }
                    }
                ))
            } header: { Text("待办设置") }

        }
    }
}
