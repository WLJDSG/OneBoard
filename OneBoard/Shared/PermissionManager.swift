import AppKit
import SwiftUI
import IOKit.hid
import UserNotifications

// MARK: - 权限管理器

final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }
    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }
    var hasInputMonitoringPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func hasNotificationPermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    @MainActor func promptAccessibilityPermission() {
        promptPermission(.accessibility)
    }

    @MainActor func promptScreenRecordingPermission() {
        promptPermission(.screenRecording)
    }

    @MainActor func promptInputMonitoringPermission() {
        promptPermission(.inputMonitoring)
    }

    @MainActor func promptNotificationPermission() {
        promptPermission(.notifications)
    }

    @MainActor func promptPermission(_ kind: OneBoardPermissionKind) {
        PermissionGuideWindowManager.shared.show(for: kind)
    }

    func openPrivacySetting(for kind: OneBoardPermissionKind) {
        let urlStr: String
        switch kind {
        case .accessibility:
            urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .inputMonitoring:
            urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .notifications:
            urlStr = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [urlStr]
        task.launch()
    }

    func openFinderExtensionSetting() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync"]
        task.launch()
    }

    func resetPrivacyAuthorizations() throws {
        try resetPrivacyAuthorizations(for: privacyBundleIdentifiers)
        syncStoredPermissionStates()
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }

    func resetPrivacyAuthorization(for kind: OneBoardPermissionKind) throws {
        let service: String
        switch kind {
        case .accessibility:
            service = "Accessibility"
        case .screenRecording:
            service = "ScreenCapture"
        case .inputMonitoring:
            service = "ListenEvent"
        case .notifications:
            service = "UserNotifications"
        }
        var failures: [Error] = []
        for bundleID in privacyBundleIdentifiers {
            do {
                try resetPrivacyAuthorization(service: service, bundleID: bundleID)
            } catch {
                failures.append(error)
            }
        }
        if let failure = failures.first {
            throw failure
        }
        syncStoredPermissionStates()
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }

    func syncStoredPermissionStates() {
        let keys = Constants.UserDefaultsKeys.self
        UserDefaults.standard.set(hasAccessibilityPermission, forKey: keys.accessibilityPermissionEnabled)
        UserDefaults.standard.set(hasScreenRecordingPermission, forKey: keys.screenRecordingPermissionEnabled)
        UserDefaults.standard.set(hasInputMonitoringPermission, forKey: keys.inputMonitoringPermissionEnabled)
    }

    private func resetPrivacyAuthorization(service: String, bundleID: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PrivacyAuthorizationResetError(service: service, status: process.terminationStatus)
        }
    }

    private var privacyBundleIdentifiers: [String] {
        let current = Bundle.main.bundleIdentifier
        let known = [
            current,
            "com.oneboard.mac",
            "com.oneboard.mac.dev",
            "com.oneboard.mac.dev2",
            "com.oneboard.mac.Findersync",
            "com.oneboard.mac.Findersync.dev",
            "com.oneboard.mac.Findersync.dev2",
        ]
        return Array(Set(known.compactMap { $0 })).sorted()
    }

    private func resetPrivacyAuthorizations(for bundleIDs: [String]) throws {
        var failures: [String] = []
        for bundleID in bundleIDs {
            for service in ["All", "Accessibility", "ScreenCapture", "ListenEvent", "SystemPolicyAllFiles", "UserNotifications"] {
                do {
                    try resetPrivacyAuthorization(service: service, bundleID: bundleID)
                } catch {
                    failures.append("\(bundleID) \(service): \(error.localizedDescription)")
                }
            }
        }

        if !failures.isEmpty {
            throw PrivacyAuthorizationResetFailures(failures: failures)
        }
    }
}

struct PrivacyAuthorizationResetError: LocalizedError {
    let service: String
    let status: Int32

    var errorDescription: String? {
        "\(service) 授权记录清除失败（退出码 \(status)）"
    }
}

struct PrivacyAuthorizationResetFailures: LocalizedError {
    let failures: [String]

    var errorDescription: String? {
        failures.joined(separator: "\n")
    }
}

// MARK: - 权限流程完成通知

extension Notification.Name {
    static let permissionFlowCompleted = Notification.Name("OneBoardPermissionFlowCompleted")
    static let systemCapabilityStatusDidChange = Notification.Name("OneBoardSystemCapabilityStatusDidChange")
}

enum OneBoardPermissionKind: Equatable {
    case accessibility
    case screenRecording
    case inputMonitoring
    case notifications

    var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        case .inputMonitoring: return "输入监控"
        case .notifications: return "通知"
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "record.circle"
        case .inputMonitoring: return "keyboard.badge.eye"
        case .notifications: return "bell.badge"
        }
    }

    var guideText: String {
        switch self {
        case .accessibility:
            return "把 OneBoard 拖到右侧列表，打开开关"
        case .screenRecording:
            return "把 OneBoard 拖到右侧列表，打开开关后重启 App"
        case .inputMonitoring:
            return "把 OneBoard 拖到右侧列表，打开开关后重启 App"
        case .notifications:
            return "在系统设置里允许 OneBoard 发送通知"
        }
    }
}

// MARK: - 权限引导窗口管理

@MainActor
final class PermissionGuideWindowManager {
    static let shared = PermissionGuideWindowManager()

    private var panel: NSPanel?
    private var timer: Timer?
    private var currentKind: OneBoardPermissionKind?
    private var isRevoke: Bool = false
    private var flowStartTime: Date = Date()  // 最短保护期，防权限 API 缓存误判

    var hasActiveFlow: Bool { currentKind != nil }

    private init() {}

    func show(for kind: OneBoardPermissionKind, revokeMode: Bool = false) {
        // 先清理上一个流程
        hide()

        currentKind = kind
        isRevoke = revokeMode
        flowStartTime = Date()  // 重置保护期

        // 打开系统设置
        PermissionManager.shared.openPrivacySetting(for: kind)

        // revoke 模式：只开系统设置 + 轮询，不显示引导窗
        if revokeMode {
            startPolling()
            return
        }

        // 授权模式：显示引导悬浮窗
        showGuidePanel(kind: kind)
        startPolling()
    }

    private func showGuidePanel(kind: OneBoardPermissionKind) {
        let view = NSHostingView(rootView: PermissionGuideView(kind: kind) { [weak self] in
            self?.hide()
        })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 118),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = view
        positionGuidePanel(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        self.panel?.close()
        self.panel = panel
    }

    private func positionGuidePanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - panel.frame.width - 28
        let y = frame.maxY - panel.frame.height - 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        currentKind = nil
        isRevoke = false
    }

    // MARK: - 轮询

    private func startPolling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkPermission() {
        guard let kind = currentKind else { return }

        // 最短保护期 1.5s：防止 AXIsProcessTrusted / CGPreflightScreenCaptureAccess 返回缓存值
        // 导致流程刚启动就被误判为「已完成」而关闭悬浮框
        guard Date().timeIntervalSince(flowStartTime) > 1.5 else { return }

        let granted: Bool
        switch kind {
        case .accessibility:    granted = PermissionManager.shared.hasAccessibilityPermission
        case .screenRecording:  granted = PermissionManager.shared.hasScreenRecordingPermission
        case .inputMonitoring:  granted = PermissionManager.shared.hasInputMonitoringPermission
        case .notifications:
            Task { @MainActor in
                let granted = await PermissionManager.shared.hasNotificationPermission()
                let completed = self.isRevoke ? !granted : granted
                guard completed else { return }
                self.finishFlow()
            }
            return
        }

        let completed = isRevoke ? !granted : granted
        guard completed else { return }

        // revoke 模式还需要等用户关闭系统设置
        if isRevoke && isSystemSettingsRunning() { return }

        finishFlow()
    }

    private func finishFlow() {
        hide()

        // 恢复设置窗口 + 通知刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PermissionManager.shared.syncStoredPermissionStates()
            SettingsWindowManager.shared.bringToFront()
            NotificationCenter.default.post(name: .permissionFlowCompleted, object: nil)
            NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
        }
    }

    private func isSystemSettingsRunning() -> Bool {
        let ids = ["com.apple.SystemSettings", "com.apple.systempreferences"]
        return NSWorkspace.shared.runningApplications.contains { ids.contains($0.bundleIdentifier ?? "") }
    }
}

// MARK: - 权限引导视图

private struct PermissionGuideView: View {
    let kind: OneBoardPermissionKind
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 48, height: 48)
                    .shadow(radius: 4, y: 2)
                    .onDrag {
                        NSItemProvider(object: Bundle.main.bundleURL as NSURL)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("开启 \(kind.title)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(kind.guideText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开设置") {
                        PermissionManager.shared.openPrivacySetting(for: kind)
                    }
                    .controlSize(.small)
                }
            }
            .padding(14)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(width: 250, height: 118)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}
