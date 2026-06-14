import SwiftUI
import KeyboardShortcuts

enum SettingsTab: String {
    case general
    case authorization
    case hotkeys
    case gateway
    case recognition
    case about
}

@main
struct OneBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// 设置窗口管理器
@MainActor
final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private override init() {}

    func show(selectedTab: SettingsTab = .general) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(selectedTab.rawValue, forKey: Constants.UserDefaultsKeys.selectedSettingsTab)

        if let window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
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

    /// 将已存在的设置窗口恢复到前台（不居中，不改位置）
    func bringToFront() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // 不置空 window，以便后续复用
    }
}

/// 设置窗口
struct SettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.maxClipboardItems) private var maxItems = Constants.defaultMaxClipboardItems
    @AppStorage(Constants.UserDefaultsKeys.retentionDays) private var retentionDays = Constants.defaultRetentionDays
    @AppStorage(Constants.UserDefaultsKeys.selectedSettingsTab) private var selectedTabRawValue = SettingsTab.general.rawValue

    // OCR / 翻译设置
    @AppStorage(Constants.UserDefaultsKeys.ocrServiceType) private var ocrServiceType = "apple"
    @AppStorage(Constants.UserDefaultsKeys.translationServiceType) private var translationServiceType = "apple"
    @AppStorage(Constants.UserDefaultsKeys.thirdPartyOCRAPIKey) private var ocrAPIKey = ""
    @AppStorage(Constants.UserDefaultsKeys.translationSourceLanguage) private var sourceLanguage = ""
    @AppStorage(Constants.UserDefaultsKeys.translationTargetLanguage) private var targetLanguage = "en"

    @StateObject private var systemCapabilities = SystemCapabilityViewModel.shared
    @StateObject private var gatewayViewModel = GatewayViewModel.shared

    var body: some View {
        TabView(selection: settingsTabSelection) {
            generalSettings
                .tabItem { Label("通用", systemImage: "gear") }
                .tag(SettingsTab.general)

            authorizationSettings
                .tabItem { Label("授权", systemImage: "lock.shield") }
                .tag(SettingsTab.authorization)

            hotkeySettings
                .tabItem { Label("快捷键", systemImage: "keyboard") }
                .tag(SettingsTab.hotkeys)

            GatewaySettingsView()
                .tabItem { Label("网关", systemImage: "network") }
                .tag(SettingsTab.gateway)

            ocrTranslationSettings
                .tabItem { Label("识别·翻译", systemImage: "text.viewfinder") }
                .tag(SettingsTab.recognition)

            aboutView
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 620, height: 540)
        .onAppear {
            systemCapabilities.refresh()
            gatewayViewModel.refreshHelperStatus()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            systemCapabilities.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .permissionFlowCompleted)) { _ in
            systemCapabilities.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .systemCapabilityStatusDidChange)) { _ in
            systemCapabilities.refresh()
            gatewayViewModel.refreshHelperStatus()
        }
    }

    private var settingsTabSelection: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectedTabRawValue) ?? .general },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    // MARK: - 通用设置

    private var generalSettings: some View {
        Form {
            Section {
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
        }
        .formStyle(.grouped)
        .padding()
    }

    private var authorizationSettings: some View {
        Form {
            Section {
                permissionToggle(
                    title: "辅助功能",
                    description: "用于拖拽摇晃唤出暂存区、全局快捷键等交互",
                    isOn: Binding(
                        get: { systemCapabilities.accessibilityGranted },
                        set: { systemCapabilities.setAccessibilityEnabled($0) }
                    ),
                    isGranted: systemCapabilities.accessibilityGranted
                )

                permissionToggle(
                    title: "屏幕录制",
                    description: "用于截图、OCR 和截图翻译",
                    isOn: Binding(
                        get: { systemCapabilities.screenRecordingGranted },
                        set: { systemCapabilities.setScreenRecordingEnabled($0) }
                    ),
                    isGranted: systemCapabilities.screenRecordingGranted
                )

                capabilityToggle(
                    title: "网关免密 Helper",
                    description: "用于网关切换时避免反复输入管理员密码",
                    isOn: systemCapabilities.gatewayHelperInstalled,
                    enable: { systemCapabilities.setGatewayHelperEnabled(true) },
                    disable: { systemCapabilities.setGatewayHelperEnabled(false) }
                )

                Toggle("开机自启", isOn: Binding(
                    get: { systemCapabilities.launchAtLoginEnabled },
                    set: { systemCapabilities.setLaunchAtLoginEnabled($0) }
                ))
            } header: {
                Text("系统能力")
            } footer: {
                if let message = systemCapabilities.errorMessage ?? systemCapabilities.statusMessage ?? gatewayViewModel.statusMessage {
                    Text(message)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func permissionToggle(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        isGranted: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: isOn)
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

    private func capabilityToggle(
        title: String,
        description: String,
        isOn: Bool,
        enable: @escaping () -> Void,
        disable: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { $0 ? enable() : disable() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Label(isOn ? "已启用" : "未启用", systemImage: isOn ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(isOn ? .green : .orange)
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

                HStack {
                    Text("翻译选中文字")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .translateSelectedText)
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

            Section {
                HStack {
                    Text("显示网关切换")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .showGatewaySwitcher)
                }
            } header: {
                Text("网关快捷键")
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
                Picker("翻译服务", selection: translationServiceSelection) {
                    ForEach(TranslationServiceType.allCases) { serviceType in
                        Text(serviceType.settingsDisplayName).tag(serviceType.rawValue)
                    }
                }

                if selectedTranslationServiceType.requiresAPIKey {
                    SecureField("API Key", text: Binding(
                        get: { UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.thirdPartyTranslationAPIKey) ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: Constants.UserDefaultsKeys.thirdPartyTranslationAPIKey) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Picker("源语言", selection: $sourceLanguage) {
                    Text("自动检测").tag("")
                    Text("英文").tag("en")
                    Text("中文（简体）").tag("zh-Hans")
                    Text("中文（繁体）").tag("zh-Hant")
                    Text("日文").tag("ja")
                    Text("韩文").tag("ko")
                    Text("法文").tag("fr")
                    Text("德文").tag("de")
                }

                Picker("目标语言", selection: $targetLanguage) {
                    Text("英文").tag("en")
                    Text("中文（简体）").tag("zh-Hans")
                    Text("中文（繁体）").tag("zh-Hant")
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

    private var translationServiceSelection: Binding<String> {
        Binding(
            get: { normalizedTranslationServiceRawValue(translationServiceType) },
            set: { translationServiceType = normalizedTranslationServiceRawValue($0) }
        )
    }

    private var selectedTranslationServiceType: TranslationServiceType {
        TranslationServiceType(rawValue: normalizedTranslationServiceRawValue(translationServiceType)) ?? .apple
    }

    private func normalizedTranslationServiceRawValue(_ rawValue: String) -> String {
        rawValue == "third_party" ? TranslationServiceType.deepSeek.rawValue : rawValue
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
