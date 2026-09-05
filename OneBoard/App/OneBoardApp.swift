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

    var subtitle: String {
        switch self {
        case .general: return "调整日常偏好，让工作空间更适合你。"
        case .authorization: return "管理系统权限与扩展能力。"
        case .hotkeys: return "让常用操作，始终触手可及。"
        case .gateway: return "查看网络状态，快速切换连接配置。"
        case .aiModels: return "连接你的模型供应商，掌握额度与用量。"
        case .codexAccounts: return "统一管理账号、订阅和可用额度。"
        case .recognition: return "从文字识别到翻译，选择适合你的服务。"
        case .todo: return "管理待办提醒、文件暂存与 Finder 扩展。"
        case .about: return "一个轻巧、专注的 macOS 效率工具。"
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
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "OneBoard 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 960, height: 680)
        window.isMovableByWindowBackground = true
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
    @AppStorage(ConfiguredAITranslationService.selectionKey) private var translationProviderID = ""
    @ObservedObject private var aiProviders = AIModelSwitcherViewModel.shared
    @AppStorage(Constants.UserDefaultsKeys.translationSourceLanguage) private var sourceLanguage = ""
    @AppStorage(Constants.UserDefaultsKeys.translationTargetLanguage) private var targetLanguage = "en"
    @AppStorage(Constants.UserDefaultsKeys.todoShowNotifications) private var todoShowNotifications = true
    @StateObject private var systemCapabilities = SystemCapabilityViewModel.shared
    @StateObject private var gatewayViewModel = GatewayViewModel.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(LinearGradient(colors: [SettingsPalette.accent, SettingsPalette.teal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OneBoard").font(.system(size: 18, weight: .bold))
                        Text("你的桌面工作空间").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 22)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        navigationGroup("工作空间", tabs: [.general, .hotkeys, .recognition, .todo])
                        navigationGroup("连接与账号", tabs: [.aiModels, .codexAccounts, .gateway])
                        navigationGroup("应用", tabs: [.authorization, .about])
                    }
                }.scrollIndicators(.hidden)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Circle().fill(SettingsPalette.teal).frame(width: 6, height: 6)
                    Text("OneBoard for macOS").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }.padding(12)
            }
            .padding(14)
            .padding(.top, 14)
            .frame(width: 214)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.04)))
            .padding(.leading, 18)
            .padding(.top, 38)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(selectedSettingsTab.title)
                            .font(.system(size: 27, weight: .bold))
                        Text(selectedSettingsTab.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: selectedSettingsTab.systemImage)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(SettingsPalette.accent.opacity(0.65))
                        .frame(width: 52, height: 52)
                        .background(SettingsPalette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 28)
                .padding(.top, 46)
                .padding(.bottom, 22)

                selectedSettingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.trailing, 10)
        }
        .frame(minWidth: 960, minHeight: 680)
        .background(SettingsBackdrop())
        .tint(SettingsPalette.accent)
        .onAppear {
            systemCapabilities.refresh()
            gatewayViewModel.refreshHelperStatus()
            ocrAPIKey = AppSettings.thirdPartyOCRAPIKey
        }
        .onReceive(NotificationCenter.default.publisher(for: .permissionFlowCompleted)) { _ in systemCapabilities.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .systemCapabilityStatusDidChange)) { _ in systemCapabilities.refresh(); gatewayViewModel.refreshHelperStatus() }
    }

    private var selectedSettingsTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRawValue) ?? .general
    }

    private func navigationGroup(_ title: String, tabs: [SettingsTab]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 13).padding(.top, 10).padding(.bottom, 5)
            ForEach(tabs) { tab in
                SettingsNavigationItem(tab: tab, selected: tab == selectedSettingsTab) {
                    selectedTabRawValue = tab.rawValue
                }
            }
        }
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
        SettingsForm {
            Section {
                HStack {
                    settingsDescription("历史记录容量", subtitle: "设置剪贴板最多保留的记录数量", icon: "square.stack")
                    Spacer()
                    Picker("最大记录条数", selection: $maxItems) { Text("100 条").tag(100); Text("200 条（默认）").tag(200); Text("500 条").tag(500); Text("1000 条").tag(1000) }
                        .labelsHidden().frame(width: 170)
                }
                HStack {
                    settingsDescription("保留时长", subtitle: "过期记录会自动清理，保持工作空间轻盈", icon: "clock")
                    Spacer()
                    Picker("保留天数", selection: $retentionDays) { Text("7 天").tag(7); Text("14 天").tag(14); Text("30 天（默认）").tag(30); Text("90 天").tag(90); Text("永久").tag(-1) }
                        .labelsHidden().frame(width: 170)
                }
            } header: { Text("剪贴板设置") }
        }
    }

    private var authorizationSettings: some View {
        SettingsForm {
            Section {
                permissionRow(title: "辅助功能", description: "用于自动粘贴、读取选中文字、全局交互", isGranted: systemCapabilities.accessibilityGranted, isRequesting: systemCapabilities.permissionRequestingKind == .accessibility, onRequest: { systemCapabilities.setAccessibilityEnabled(true) }, onRevoke: { systemCapabilities.setAccessibilityEnabled(false) })
                permissionRow(title: "屏幕录制", description: "用于截图、OCR 和截图翻译", isGranted: systemCapabilities.screenRecordingGranted, isRequesting: systemCapabilities.permissionRequestingKind == .screenRecording, onRequest: { systemCapabilities.setScreenRecordingEnabled(true) }, onRevoke: { systemCapabilities.setScreenRecordingEnabled(false) })
                permissionRow(title: "输入监控", description: "用于文件拖拽摇晃检测等全局输入监听", isGranted: systemCapabilities.inputMonitoringGranted, isRequesting: systemCapabilities.permissionRequestingKind == .inputMonitoring, onRequest: { systemCapabilities.setInputMonitoringEnabled(true) }, onRevoke: { systemCapabilities.setInputMonitoringEnabled(false) })
                permissionRow(title: "通知", description: "用于待办事项到期提醒", isGranted: systemCapabilities.notificationGranted, isRequesting: systemCapabilities.permissionRequestingKind == .notifications, onRequest: { todoShowNotifications = true; systemCapabilities.setNotificationEnabled(true) }, onRevoke: { todoShowNotifications = false; systemCapabilities.setNotificationEnabled(false) })
            } header: { Text("隐私权限") }

            Section {
                capabilityRow(title: "网关安全 Helper", description: "首次安装需管理员授权；后续切换与卸载使用 Touch ID 或登录密码确认", isGranted: systemCapabilities.gatewayHelperInstalled, onEnable: { systemCapabilities.setGatewayHelperEnabled(true) }, onDisable: { systemCapabilities.setGatewayHelperEnabled(false) })
                Toggle("开机自启", isOn: Binding(get: { systemCapabilities.launchAtLoginEnabled }, set: { systemCapabilities.setLaunchAtLoginEnabled($0) }))
            } header: { Text("系统能力") }

            Section {
                Button("打开 Finder 扩展设置") {
                    PermissionManager.shared.openFinderExtensionSetting()
                }
            } header: { Text("Finder 扩展") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let m = systemCapabilities.errorMessage ?? systemCapabilities.statusMessage ?? gatewayViewModel.statusMessage { Text(m) }
                    Text("Finder 右键新建文件需要先启用 OneBoard Finder 扩展。启用后，可在受支持的本地 Finder 文件夹空白处右键选择“新建文件”；iCloud Drive 与启用 iCloud 同步的桌面不受 Finder Sync 支持。")
                        .font(.caption).foregroundColor(SettingsPalette.muted)
                }
            }
        }
    }

    /// 按钮式权限行：状态 + 操作 分离
    private func permissionRow(title: String, description: String, isGranted: Bool, isRequesting: Bool, onRequest: @escaping () -> Void, onRevoke: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : (isRequesting ? "hourglass" : "lock.fill"))
                .font(.system(size: 18))
                .foregroundColor(isGranted ? OneBoardColors.success : (isRequesting ? SettingsPalette.accent : SettingsPalette.muted.opacity(0.65)))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    statusBadge(isGranted: isGranted, isRequesting: isRequesting)
                }
                Text(description).font(.caption).foregroundColor(SettingsPalette.muted)
            }

            Spacer()

            if isGranted {
                Button("撤销") { onRevoke() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(SettingsPalette.muted.opacity(0.65))
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
                    .fill(isGranted ? OneBoardColors.success.opacity(0.12) : (isRequesting ? SettingsPalette.accent.opacity(0.12) : OneBoardColors.warning.opacity(0.12)))
            )
            .foregroundColor(isGranted ? OneBoardColors.success : (isRequesting ? SettingsPalette.accent : OneBoardColors.warning))
    }

    /// 系统能力行
    private func capabilityRow(title: String, description: String, isGranted: Bool, onEnable: @escaping () -> Void, onDisable: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(isGranted ? OneBoardColors.success : SettingsPalette.muted.opacity(0.65))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    statusBadge(isGranted: isGranted, isRequesting: false)
                }
                Text(description).font(.caption).foregroundColor(SettingsPalette.muted)
            }

            Spacer()

            Button(isGranted ? "卸载..." : "安装") { isGranted ? onDisable() : onEnable() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(isGranted ? SettingsPalette.muted.opacity(0.65) : SettingsPalette.accent)
        }.padding(.vertical, 4)
    }

    private var hotkeySettings: some View {
        SettingsForm {
            Section { HStack { Text("显示剪贴板"); Spacer(); KeyboardShortcuts.Recorder(for: .showClipboard) } } header: { Text("剪贴板快捷键") }
            Section { HStack { Text("截图"); Spacer(); KeyboardShortcuts.Recorder(for: .captureScreenshot) }; HStack { Text("翻译选中文字"); Spacer(); KeyboardShortcuts.Recorder(for: .translateSelectedText) } } header: { Text("截图快捷键") }
            Section { HStack { Text("文件暂存架"); Spacer(); KeyboardShortcuts.Recorder(for: .showFileShelf) } } header: { Text("文件暂存快捷键") }
            Section { HStack { Text("显示网关切换"); Spacer(); KeyboardShortcuts.Recorder(for: .showGatewaySwitcher) } } header: { Text("网关快捷键") }
            Section {
                HStack { Text("显示待办面板"); Spacer(); KeyboardShortcuts.Recorder(for: .toggleTodoPanel) }
                HStack { Text("将选中文字添加到待办"); Spacer(); KeyboardShortcuts.Recorder(for: .addSelectedTextToTodo) }
            } header: { Text("待办快捷键") }
        }
    }

    private var ocrTranslationSettings: some View {
        SettingsForm {
            Section {
                LabeledContent("OCR 服务") {
                    Picker("OCR 服务", selection: $ocrServiceType) { Text("Apple Vision（离线免费）").tag("apple"); Text("第三方 API").tag("third_party") }.labelsHidden().frame(width: 230)
                }
                if ocrServiceType == "third_party" {
                    SecureField("API Key", text: secretBinding($ocrAPIKey) { AppSettings.thirdPartyOCRAPIKey = $0 })
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("识别语言") {
                    Picker("识别语言", selection: Binding(get: { UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrLanguage) ?? "zh-Hans" }, set: { UserDefaults.standard.set($0, forKey: Constants.UserDefaultsKeys.ocrLanguage) })) {
                    Text("中文（简体）").tag("zh-Hans"); Text("中文（繁体）").tag("zh-Hant"); Text("英文").tag("en-US"); Text("日文").tag("ja-JP"); Text("韩文").tag("ko-KR")
                }.labelsHidden().frame(width: 230)
                }
            } header: { Text("OCR 文字识别") }
            Section {
                LabeledContent("翻译服务") {
                    Picker("翻译服务", selection: translationServiceSelection) { ForEach(TranslationServiceType.allCases) { Text($0.settingsDisplayName).tag($0.rawValue) } }.labelsHidden().frame(width: 230)
                }
                if selectedTranslationServiceType.requiresAPIKey {
                    LabeledContent("翻译 API Key") {
                    Picker("翻译 API Key", selection: $translationProviderID) {
                        Text("请选择已添加的 API Key").tag("")
                        ForEach(aiProviders.profiles.filter { $0.kind == .custom && aiProviders.hasSavedAPIKey(for: $0) }) { profile in
                            Text("\(profile.title) · \(profile.client.title)").tag(profile.id.uuidString)
                        }
                    }.labelsHidden().frame(width: 230)
                }
                    Text("复用 AI 模型页配置的连接、API Key 和默认模型；可在翻译窗口临时切换。")
                        .font(.caption).foregroundColor(SettingsPalette.muted)
                }
                LabeledContent("源语言") {
                    Picker("源语言", selection: $sourceLanguage) { Text("自动检测").tag(""); Text("英文").tag("en"); Text("中文（简体）").tag("zh-Hans"); Text("中文（繁体）").tag("zh-Hant"); Text("日文").tag("ja"); Text("韩文").tag("ko"); Text("法文").tag("fr"); Text("德文").tag("de") }.labelsHidden().frame(width: 230)
                }
                LabeledContent("目标语言") {
                    Picker("目标语言", selection: $targetLanguage) { Text("英文").tag("en"); Text("中文（简体）").tag("zh-Hans"); Text("中文（繁体）").tag("zh-Hant"); Text("日文").tag("ja"); Text("韩文").tag("ko"); Text("法文").tag("fr"); Text("德文").tag("de") }.labelsHidden().frame(width: 230)
                }
            } header: { Text("翻译") }
        }
    }

    private var translationServiceSelection: Binding<String> { Binding(get: { TranslationServiceType(rawValue: translationServiceType == "third_party" ? TranslationServiceType.deepSeek.rawValue : translationServiceType)?.rawValue ?? "apple" }, set: { translationServiceType = $0 }) }
    private var selectedTranslationServiceType: TranslationServiceType { TranslationServiceType(rawValue: translationServiceType == "third_party" ? TranslationServiceType.deepSeek.rawValue : translationServiceType) ?? .apple }

    private func secretBinding(_ state: Binding<String>, save: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { state.wrappedValue }, set: { value in state.wrappedValue = value; save(value) })
    }

    private func settingsDescription(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(SettingsPalette.accent)
                .frame(width: 40, height: 40)
                .background(SettingsPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var aboutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsCard {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 38)).foregroundStyle(.white)
                            .frame(width: 88, height: 88)
                            .background(LinearGradient(colors: [SettingsPalette.accent, SettingsPalette.teal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
                            .shadow(color: SettingsPalette.accent.opacity(0.15), radius: 15, y: 8)
                        Text(Constants.appName).font(.system(size: 30, weight: .bold))
                        Text("让桌面上的每一步，更轻松。")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                        Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(SettingsPalette.accent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(SettingsPalette.accent.opacity(0.07), in: Capsule())
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                SettingsCard {
                    VStack(alignment: .leading, spacing: 24) {
                        settingsDescription("捕捉与整理", subtitle: "截图标注、剪贴板历史、待办和文件暂存", icon: "square.on.square")
                        settingsDescription("连接与协作", subtitle: "模型供应商、Codex 账号、识别和翻译", icon: "point.3.connected.trianglepath.dotted")
                        settingsDescription("为 macOS 而生", subtitle: "原生体验，与你的桌面自然融为一体", icon: "macwindow")
                    }.padding(24)
                }
            }.padding(.horizontal, 28).padding(.bottom, 28)
        }.scrollIndicators(.hidden)
    }
}
