import SwiftUI

/// 文件暂存入口与 Finder 文件类型配置。
struct FileSettingsView: View {
    @State private var enabledTypes = ["txt", "docx", "xlsx"]
    @State private var customExtension = ""
    @State private var error: String?
    private var kinds: [FinderFileKind] {
        let builtins = FinderFileKind.allCases
        return builtins + enabledTypes.compactMap(FinderFileKind.init(rawValue:)).filter { !builtins.contains($0) }
    }
    var body: some View {
        SettingsForm {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("文件暂存区")
                        Text("拖入普通文件临时收集，再拖到目标应用；移除暂存项不会删除原文件。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开暂存区") { FileStagingViewModel.shared.showFloatingShelf() }
                }
            } header: { Text("文件暂存") }
            Section {
                ForEach(kinds, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { enabledTypes.contains(kind.rawValue) },
                        set: { enabled in
                            if enabled { enabledTypes.append(kind.rawValue) }
                            else { enabledTypes.removeAll { $0 == kind.rawValue } }
                        }
                    )).toggleStyle(.switch)
                }
                HStack {
                    TextField("自定义后缀，例如 vue、log、conf", text: $customExtension)
                    Button("添加") { addExtension() }.disabled(customExtension.isEmpty)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Text("自定义后缀创建空文件，不会自动生成专有格式模板。Pages、Numbers、Keynote、WPS、PowerPoint 等文档请通过对应应用新建，不能用空文件冒充。")
                    .font(.caption).foregroundStyle(.secondary)
                Menu("在桌面新建文件") {
                    ForEach(enabledTypes.compactMap(FinderFileKind.init(rawValue:)), id: \.self) { kind in
                        Button(kind.title) { DesktopFileCreation.create(kind: kind) }
                    }
                }
            } header: { Text("Finder 右键新建文件类型") } footer: {
                Text("Word、Excel、RTF、JSON、XML、HTML 使用内置空白模板。其他类型创建空文本文件。iCloud 桌面请使用菜单栏或上方的桌面新建入口。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            enabledTypes = UserDefaults(suiteName: Constants.appGroupIdentifier)?.stringArray(forKey: Constants.UserDefaultsKeys.enabledFileTypes) ?? ["txt", "docx", "xlsx"]
        }
        .onChange(of: enabledTypes) { _, value in
            UserDefaults(suiteName: Constants.appGroupIdentifier)?.set(value, forKey: Constants.UserDefaultsKeys.enabledFileTypes)
        }
    }
    private func addExtension() {
        var raw = customExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix(".") { raw.removeFirst() }
        guard let kind = FinderFileKind(rawValue: raw) else {
            error = "后缀最多 32 个字符，仅支持字母、数字及中间的点、短横线、下划线。"
            return
        }
        if !enabledTypes.contains(kind.rawValue) { enabledTypes.append(kind.rawValue) }
        customExtension = ""; error = nil
    }
}
