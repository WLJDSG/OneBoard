import SwiftUI
import AppKit
import KeyboardShortcuts

// 入口点已移至 App_minimal/main.swift（模块隔离架构）
// 此文件仅保留设置窗口相关类型

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case authorization
    case hotkeys
    case gateway
    case aiModels
    case codexAccounts
    case recognition
    case todo
    case about

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .authorization: return "授权"
        case .hotkeys: return "快捷键"
        case .gateway: return "网关"
        case .aiModels: return "AI 模型"
        case .codexAccounts: return "Codex 账号"
        case .recognition: return "识别·翻译"
        case .todo: return "待办·文件"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .authorization: return "lock.shield"
        case .hotkeys: return "keyboard"
        case .gateway: return "network"
        case .aiModels: return "point.3.connected.trianglepath.dotted"
        case .codexAccounts: return "person.2"
        case .recognition: return "text.viewfinder"
        case .todo: return "checklist"
        case .about: return "info.circle"
        }
    }
}

/// 设置窗口管理器
@MainActor
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private override init() {}

    public func show(selectedTab: SettingsTab = .general) {
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
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
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

    public func bringToFront() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil) }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    public func windowWillClose(_ notification: Notification) {}
}

struct SettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.maxClipboardItems) private var maxItems = Constants.defaultMaxClipboardItems
    @AppStorage(Constants.UserDefaultsKeys.retentionDays) private var retentionDays = Constants.defaultRetentionDays
    @AppStorage(Constants.UserDefaultsKeys.selectedSettingsTab) private var selectedTabRawValue = SettingsTab.general.rawValue
    @AppStorage(Constants.UserDefaultsKeys.ocrServiceType) private var ocrServiceType = "apple"
    @AppStorage(Constants.UserDefaultsKeys.translationServiceType) private var translationServiceType = "apple"
    @State private var ocrAPIKey = ""
    @State private var translationAPIKey = ""
    @AppStorage(Constants.UserDefaultsKeys.translationSourceLanguage) private var sourceLanguage = ""
    @AppStorage(Constants.UserDefaultsKeys.translationTargetLanguage) private var targetLanguage = "en"
    @AppStorage(Constants.UserDefaultsKeys.todoShowNotifications) private var todoShowNotifications = true
    @StateObject private var systemCapabilities = SystemCapabilityViewModel.shared
    @StateObject private var gatewayViewModel = GatewayViewModel.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(SettingsTab.allCases, selection: settingsTabSelection) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 190)
            .background(.bar)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSettingsTab.title)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                selectedSettingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 780, height: 620)
        .onAppear {
            systemCapabilities.refresh()
            gatewayViewModel.refreshHelperStatus()
            ocrAPIKey = AppSettings.thirdPartyOCRAPIKey
            translationAPIKey = AppSettings.thirdPartyTranslationAPIKey
        }
        .onReceive(NotificationCenter.default.publisher(for: .permissionFlowCompleted)) { _ in systemCapabilities.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .systemCapabilityStatusDidChange)) { _ in systemCapabilities.refresh(); gatewayViewModel.refreshHelperStatus() }
    }

    private var selectedSettingsTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .general
    }

    private var settingsTabSelection: Binding<SettingsTab?> {
        Binding(
            get: { selectedSettingsTab },
            set: { selectedTabRawValue = ($0 ?? .general).rawValue }
        )
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSettingsTab {
        case .general:
            generalSettings
        case .authorization:
            authorizationSettings
        case .hotkeys:
            hotkeySettings
        case .gateway:
            GatewaySettingsView()
        case .aiModels:
            AIModelSettingsView()
        case .codexAccounts:
            CodexAccountSettingsView()
        case .recognition:
            ocrTranslationSettings
        case .todo:
            TodoSettingsView()
        case .about:
            aboutView
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker("最大记录条数", selection: $maxItems) { Text("100 条").tag(100); Text("200 条（默认）").tag(200); Text("500 条").tag(500); Text("1000 条").tag(1000) }
                Picker("保留天数", selection: $retentionDays) { Text("7 天").tag(7); Text("14 天").tag(14); Text("30 天（默认）").tag(30); Text("90 天").tag(90); Text("永久").tag(-1) }
            } header: { Text("剪贴板设置") }
        }.formStyle(.grouped).padding()
    }

    private var authorizationSettings: some View {
        Form {
            Section {
                permissionRow(title: "辅助功能", description: "用于自动粘贴、读取选中文字、全局交互", isGranted: systemCapabilities.accessibilityGranted, isRequesting: systemCapabilities.permissionRequestingKind == .accessibility, onRequest: { systemCapabilities.setAccessibilityEnabled(true) }, onRevoke: { systemCapabilities.setAccessibilityEnabled(false) })
                permissionRow(title: "屏幕录制", description: "用于截图、OCR 和截图翻译", isGranted: systemCapabilities.screenRecordingGranted, isRequesting: systemCapabilities.permissionRequestingKind == .screenRecording, onRequest: { systemCapabilities.setScreenRecordingEnabled(true) }, onRevoke: { systemCapabilities.setScreenRecordingEnabled(false) })
                permissionRow(title: "输入监控", description: "用于文件拖拽摇晃检测等全局输入监听", isGranted: systemCapabilities.inputMonitoringGranted, isRequesting: systemCapabilities.permissionRequestingKind == .inputMonitoring, onRequest: { systemCapabilities.setInputMonitoringEnabled(true) }, onRevoke: { systemCapabilities.setInputMonitoringEnabled(false) })
                permissionRow(title: "通知", description: "用于待办事项到期提醒", isGranted: systemCapabilities.notificationGranted, isRequesting: systemCapabilities.permissionRequestingKind == .notifications, onRequest: { todoShowNotifications = true; systemCapabilities.setNotificationEnabled(true) }, onRevoke: { todoShowNotifications = false; systemCapabilities.setNotificationEnabled(false) })
            } header: { Text("隐私权限") }

            Section {
                capabilityRow(title: "网关免密 Helper", description: "用于网关切换时避免反复输入管理员密码", isGranted: systemCapabilities.gatewayHelperInstalled, onEnable: { systemCapabilities.setGatewayHelperEnabled(true) }, onDisable: { systemCapabilities.setGatewayHelperEnabled(false) })
                Toggle("开机自启", isOn: Binding(get: { systemCapabilities.launchAtLoginEnabled }, set: { systemCapabilities.setLaunchAtLoginEnabled($0) }))
            } header: { Text("系统能力") }

            Section {
                Button("打开 Finder 扩展设置") {
                    PermissionManager.shared.openFinderExtensionSetting()
                }
            } header: { Text("Finder 扩展") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let m = systemCapabilities.errorMessage ?? systemCapabilities.statusMessage ?? gatewayViewModel.statusMessage { Text(m) }
                    Text("Finder 右键新建文件需要先启用 OneBoard Finder 扩展。启用后，在桌面或 Finder 文件夹空白处右键，选择“新建文件”。")
                        .font(.caption).foregroundColor(OneBoardColors.textSecondary)
                }
            }
        }.formStyle(.grouped).padding()
    }

    /// 按钮式权限行：状态 + 操作 分离
    private func permissionRow(title: String, description: String, isGranted: Bool, isRequesting: Bool, onRequest: @escaping () -> Void, onRevoke: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : (isRequesting ? "hourglass" : "lock.fill"))
                .font(.system(size: 18))
                .foregroundColor(isGranted ? OneBoardColors.success : (isRequesting ? OneBoardColors.accent : OneBoardColors.textTertiary))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    statusBadge(isGranted: isGranted, isRequesting: isRequesting)
                }
                Text(description).font(.caption).foregroundColor(OneBoardColors.textSecondary)
            }

            Spacer()

            if isGranted {
                Button("撤销") { onRevoke() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(OneBoardColors.textTertiary)
            } else {
                Button(isRequesting ? "请求中..." : "去开启") { onRequest() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRequesting)
            }
        }.padding(.vertical, 4)
    }

    private func statusBadge(isGranted: Bool, isRequesting: Bool) -> some View {
        Text(isGranted ? "已授权" : (isRequesting ? "请求中..." : "未授权"))
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isGranted ? OneBoardColors.success.opacity(0.12) : (isRequesting ? OneBoardColors.accent.opacity(0.12) : OneBoardColors.warning.opacity(0.12)))
            )
            .foregroundColor(isGranted ? OneBoardColors.success : (isRequesting ? OneBoardColors.accent : OneBoardColors.warning))
    }

    /// 系统能力行
    private func capabilityRow(title: String, description: String, isGranted: Bool, onEnable: @escaping () -> Void, onDisable: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(isGranted ? OneBoardColors.success : OneBoardColors.textTertiary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    statusBadge(isGranted: isGranted, isRequesting: false)
                }
                Text(description).font(.caption).foregroundColor(OneBoardColors.textSecondary)
            }

            Spacer()

            Button(isGranted ? "卸载..." : "安装") { isGranted ? onDisable() : onEnable() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(isGranted ? OneBoardColors.textTertiary : OneBoardColors.accent)
        }.padding(.vertical, 4)
    }

    private var hotkeySettings: some View {
        Form {
            Section { HStack { Text("显示剪贴板"); Spacer(); KeyboardShortcuts.Recorder(for: .showClipboard) } } header: { Text("剪贴板快捷键") }
            Section { HStack { Text("截图"); Spacer(); KeyboardShortcuts.Recorder(for: .captureScreenshot) }; HStack { Text("翻译选中文字"); Spacer(); KeyboardShortcuts.Recorder(for: .translateSelectedText) } } header: { Text("截图快捷键") }
            Section { HStack { Text("文件暂存架"); Spacer(); KeyboardShortcuts.Recorder(for: .showFileShelf) } } header: { Text("文件暂存快捷键") }
            Section { HStack { Text("显示网关切换"); Spacer(); KeyboardShortcuts.Recorder(for: .showGatewaySwitcher) } } header: { Text("网关快捷键") }
            Section {
                HStack { Text("显示待办面板"); Spacer(); KeyboardShortcuts.Recorder(for: .toggleTodoPanel) }
                HStack { Text("将选中文字添加到待办"); Spacer(); KeyboardShortcuts.Recorder(for: .addSelectedTextToTodo) }
            } header: { Text("待办快捷键") }
        }.formStyle(.grouped).padding()
    }

    private var ocrTranslationSettings: some View {
        Form {
            Section {
                Picker("OCR 服务", selection: $ocrServiceType) { Text("Apple Vision（离线免费）").tag("apple"); Text("第三方 API").tag("third_party") }
                if ocrServiceType == "third_party" {
                    SecureField("API Key", text: secretBinding($ocrAPIKey) { AppSettings.thirdPartyOCRAPIKey = $0 })
                        .textFieldStyle(.roundedBorder)
                }
                Picker("识别语言", selection: Binding(get: { UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrLanguage) ?? "zh-Hans" }, set: { UserDefaults.standard.set($0, forKey: Constants.UserDefaultsKeys.ocrLanguage) })) {
                    Text("中文（简体）").tag("zh-Hans"); Text("中文（繁体）").tag("zh-Hant"); Text("英文").tag("en-US"); Text("日文").tag("ja-JP"); Text("韩文").tag("ko-KR")
                }
            } header: { Text("OCR 文字识别") }
            Section {
                Picker("翻译服务", selection: translationServiceSelection) { ForEach(TranslationServiceType.allCases) { Text($0.settingsDisplayName).tag($0.rawValue) } }
                if selectedTranslationServiceType.requiresAPIKey {
                    SecureField("API Key", text: secretBinding($translationAPIKey) { AppSettings.thirdPartyTranslationAPIKey = $0 })
                        .textFieldStyle(.roundedBorder)
                }
                Picker("源语言", selection: $sourceLanguage) { Text("自动检测").tag(""); Text("英文").tag("en"); Text("中文（简体）").tag("zh-Hans"); Text("中文（繁体）").tag("zh-Hant"); Text("日文").tag("ja"); Text("韩文").tag("ko"); Text("法文").tag("fr"); Text("德文").tag("de") }
                Picker("目标语言", selection: $targetLanguage) { Text("英文").tag("en"); Text("中文（简体）").tag("zh-Hans"); Text("中文（繁体）").tag("zh-Hant"); Text("日文").tag("ja"); Text("韩文").tag("ko"); Text("法文").tag("fr"); Text("德文").tag("de") }
            } header: { Text("翻译") }
        }.formStyle(.grouped).padding()
    }

    private var translationServiceSelection: Binding<String> { Binding(get: { TranslationServiceType(rawValue: translationServiceType == "third_party" ? TranslationServiceType.deepSeek.rawValue : translationServiceType)?.rawValue ?? "apple" }, set: { translationServiceType = $0 }) }
    private var selectedTranslationServiceType: TranslationServiceType { TranslationServiceType(rawValue: translationServiceType == "third_party" ? TranslationServiceType.deepSeek.rawValue : translationServiceType) ?? .apple }

    private func secretBinding(_ state: Binding<String>, save: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { state.wrappedValue }, set: { value in state.wrappedValue = value; save(value) })
    }

    private var aboutView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.on.square").font(.system(size: 48)).foregroundColor(OneBoardColors.accent)
            Text(Constants.appName).font(.title).fontWeight(.semibold)
            Text("截图 · 剪贴板 · 文件暂存").font(.subheadline).foregroundColor(OneBoardColors.textSecondary)
            Text("版本 1.0.0").font(.caption).foregroundColor(OneBoardColors.textSecondary.opacity(0.6))
            Spacer()
            VStack(spacing: 8) {
                Text("一键管理你的剪贴板、截图和文件").font(.caption).foregroundColor(OneBoardColors.textSecondary)
                Text("Made with ❤️").font(.caption2).foregroundColor(OneBoardColors.textSecondary.opacity(0.5))
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
