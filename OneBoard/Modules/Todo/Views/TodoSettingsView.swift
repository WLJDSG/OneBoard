import SwiftUI

/// 待办事项 & Finder 文件类型设置页
struct TodoSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.todoRetentionDays) private var retentionDays = -1
    @AppStorage(Constants.UserDefaultsKeys.todoAutoRetractDelay) private var autoRetractDelay = 1.0
    @AppStorage(Constants.UserDefaultsKeys.todoShowNotifications) private var showNotifications = true

    // 文件类型（存储到共享 UserDefaults 供 Finder Sync Extension 读取）
    @State private var txtEnabled: Bool = true
    @State private var docxEnabled: Bool = true
    @State private var xlsxEnabled: Bool = true

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

            // Finder 新建文件类型管理
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("纯文本文档 (.txt)")
                        Text("创建 UTF-8 编码的空白文本文件").font(.caption).foregroundColor(SettingsPalette.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $txtEnabled).toggleStyle(.switch).labelsHidden()
                }.padding(.vertical, 4)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Word 文档 (.docx)")
                        Text("创建空白 Word 文档").font(.caption).foregroundColor(SettingsPalette.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $docxEnabled).toggleStyle(.switch).labelsHidden()
                }.padding(.vertical, 4)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Excel 表格 (.xlsx)")
                        Text("创建空白 Excel 表格").font(.caption).foregroundColor(SettingsPalette.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $xlsxEnabled).toggleStyle(.switch).labelsHidden()
                }.padding(.vertical, 4)

            } header: { Text("Finder 右键新建文件类型") } footer: {
                Text("启用 Finder 扩展后，可在受支持的本地 Finder 文件夹中右键新建文件。iCloud Drive（包括启用 iCloud 同步的桌面）由系统 File Provider 管理，macOS 不允许第三方 Finder Sync 在其空白处添加此菜单。")
                    .font(.caption).foregroundColor(SettingsPalette.muted)
            }

        }
        .onAppear { loadFileTypeSettings() }
        .onChange(of: txtEnabled) { _ in saveFileTypeSettings() }
        .onChange(of: docxEnabled) { _ in saveFileTypeSettings() }
        .onChange(of: xlsxEnabled) { _ in saveFileTypeSettings() }
    }

    // MARK: - 文件类型持久化（共享 UserDefaults）

    private func loadFileTypeSettings() {
        let shared = UserDefaults(suiteName: Constants.appGroupIdentifier)
        let types = shared?.stringArray(forKey: Constants.UserDefaultsKeys.enabledFileTypes) ?? ["txt", "docx", "xlsx"]
        txtEnabled = types.contains("txt")
        docxEnabled = types.contains("docx")
        xlsxEnabled = types.contains("xlsx")
    }

    private func saveFileTypeSettings() {
        var types: [String] = []
        if txtEnabled { types.append("txt") }
        if docxEnabled { types.append("docx") }
        if xlsxEnabled { types.append("xlsx") }
        let shared = UserDefaults(suiteName: Constants.appGroupIdentifier)
        shared?.set(types, forKey: Constants.UserDefaultsKeys.enabledFileTypes)
    }
}
