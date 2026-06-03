import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

@main
struct OneBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 设置窗口
        Settings {
            SettingsView()
        }
    }
}

/// 设置窗口（后续阶段会拆分为多个 Tab）
struct SettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.maxClipboardItems) private var maxItems = Constants.defaultMaxClipboardItems
    @AppStorage(Constants.UserDefaultsKeys.retentionDays) private var retentionDays = Constants.defaultRetentionDays
    @AppStorage(Constants.UserDefaultsKeys.launchAtLogin) private var launchAtLogin = false

    // OCR / 翻译设置
    @AppStorage(Constants.UserDefaultsKeys.ocrServiceType) private var ocrServiceType = "apple"
    @AppStorage(Constants.UserDefaultsKeys.translationServiceType) private var translationServiceType = "apple"
    @AppStorage(Constants.UserDefaultsKeys.thirdPartyOCRAPIKey) private var ocrAPIKey = ""
    @AppStorage(Constants.UserDefaultsKeys.translationTargetLanguage) private var targetLanguage = "en"

    var body: some View {
        TabView {
            // 通用设置
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            // 快捷键设置
            hotkeySettings
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            // 关于
            aboutView
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 380)
    }

    // MARK: - 通用设置

    private var generalSettings: some View {
        Form {
            Section {
                Toggle("开机自启", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        LaunchAtLogin.isEnabled = launchAtLogin
                    }

                Picker("最大记录条数", selection: $maxItems) {
                    Text("100 条").tag(100)
                    Text("200 条（默认）").tag(200)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                }

                Picker("保留天数", selection: $retentionDays) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天（默认）").tag(30)
                    Text("90 天").tag(90)
                    Text("永久").tag(-1)
                }
            } header: {
                Text("剪贴板设置")
            }

            Section {
                Link("打开辅助功能设置...", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                Text("OneBoard 需要辅助功能权限以监听全局快捷键和粘贴内容")

                if !PermissionManager.shared.hasAccessibilityPermission {
                    Label("未授权", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    Label("已授权", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            } header: {
                Text("权限")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - 快捷键设置

    private var hotkeySettings: some View {
        Form {
            Section {
                HStack {
                    Text("显示剪贴板")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .showClipboard)
                }
            } header: {
                Text("剪贴板快捷键")
            }

            Section {
                HStack {
                    Text("截图")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .captureScreenshot)
                }
            } header: {
                Text("截图快捷键")
            }

            Section {
                HStack {
                    Text("文件暂存架")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .showFileShelf)
                }
            } header: {
                Text("文件暂存快捷键")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - 关于

    private var aboutView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "square.on.square")
                .font(.system(size: 48))
                .foregroundColor(OneBoardColors.primary)

            Text(Constants.appName)
                .font(.title)
                .fontWeight(.semibold)

            Text("截图 · 剪贴板 · 文件暂存")
                .font(.subheadline)
                .foregroundColor(OneBoardColors.textSecondary)

            Text("版本 1.0.0")
                .font(.caption)
                .foregroundColor(OneBoardColors.textSecondary.opacity(0.6))

            Spacer()

            VStack(spacing: 8) {
                Text("一键管理你的剪贴板、截图和文件")
                    .font(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                Text("Made with ❤️")
                    .font(.caption2)
                    .foregroundColor(OneBoardColors.textSecondary.opacity(0.5))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}