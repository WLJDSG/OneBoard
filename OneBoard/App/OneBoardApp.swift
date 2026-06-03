import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

@main
struct OneBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// 设置窗口管理器，避免菜单栏应用依赖私有 showSettingsWindow: selector。
@MainActor
final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private override init() {}

    func show() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OneBoard 设置"
        window.contentView = hostingView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
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
    @AppStorage(Constants.UserDefaultsKeys.accessibilityPermissionEnabled) private var accessibilityEnabled = false
    @AppStorage(Constants.UserDefaultsKeys.screenRecordingPermissionEnabled) private var screenRecordingEnabled = false

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

            // OCR / 翻译
            ocrTranslationSettings
                .tabItem {
                    Label("识别·翻译", systemImage: "text.viewfinder")
                }

            // 关于
            aboutView
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 420)
        .onAppear(perform: syncPermissionSwitches)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            syncPermissionSwitches()
        }
    }

    private func syncPermissionSwitches() {
        guard !PermissionGuideWindowManager.shared.hasActiveFlow else { return }
        accessibilityEnabled = PermissionManager.shared.hasAccessibilityPermission
        screenRecordingEnabled = PermissionManager.shared.hasScreenRecordingPermission
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
                permissionToggle(
                    title: "辅助功能",
                    description: "用于拖拽摇晃唤出暂存区、模拟粘贴等全局交互",
                    isOn: $accessibilityEnabled,
                    isGranted: PermissionManager.shared.hasAccessibilityPermission,
                    enable: {
                        PermissionGuideWindowManager.shared.show(for: .accessibility)
                    },
                    disable: {
                        PermissionManager.shared.openAccessibilitySettings()
                        PermissionGuideWindowManager.shared.show(for: .accessibility, revokeMode: true)
                    }
                )

                permissionToggle(
                    title: "屏幕录制",
                    description: "用于截图、OCR 和截图翻译",
                    isOn: $screenRecordingEnabled,
                    isGranted: PermissionManager.shared.hasScreenRecordingPermission,
                    enable: {
                        PermissionGuideWindowManager.shared.show(for: .screenRecording)
                    },
                    disable: {
                        PermissionManager.shared.openScreenRecordingSettings()
                        PermissionGuideWindowManager.shared.show(for: .screenRecording, revokeMode: true)
                    }
                )
            } header: {
                Text("必要权限")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func permissionToggle(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        isGranted: Bool,
        enable: @escaping () -> Void,
        disable: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue || isGranted },
                set: { enabled in
                    isOn.wrappedValue = enabled
                    enabled ? enable() : disable()
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Label(isGranted ? "已授权" : "未授权", systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(isGranted ? .green : .orange)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    // MARK: - OCR / 翻译设置

    private var ocrTranslationSettings: some View {
        Form {
            Section {
                Picker("OCR 服务", selection: $ocrServiceType) {
                    Text("Apple Vision（离线免费）").tag("apple")
                    Text("第三方 API").tag("third_party")
                }

                if ocrServiceType == "third_party" {
                    SecureField("API Key", text: $ocrAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("识别语言", selection: Binding(
                    get: { UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrLanguage) ?? "zh-Hans" },
                    set: { UserDefaults.standard.set($0, forKey: Constants.UserDefaultsKeys.ocrLanguage) }
                )) {
                    Text("中文（简体）").tag("zh-Hans")
                    Text("中文（繁体）").tag("zh-Hant")
                    Text("英文").tag("en-US")
                    Text("日文").tag("ja-JP")
                    Text("韩文").tag("ko-KR")
                }
            } header: {
                Text("OCR 文字识别")
            }

            Section {
                Picker("翻译服务", selection: $translationServiceType) {
                    Text("DeepSeek AI 翻译").tag("third_party")
                    Text("Apple Translation（macOS 15+）").tag("apple")
                }

                if translationServiceType == "third_party" {
                    SecureField("API Key", text: Binding(
                        get: { UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.thirdPartyTranslationAPIKey) ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: Constants.UserDefaultsKeys.thirdPartyTranslationAPIKey) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Picker("目标语言", selection: $targetLanguage) {
                    Text("英文").tag("en")
                    Text("中文（简体）").tag("zh-Hans")
                    Text("日文").tag("ja")
                    Text("韩文").tag("ko")
                    Text("法文").tag("fr")
                    Text("德文").tag("de")
                }
            } header: {
                Text("翻译")
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
