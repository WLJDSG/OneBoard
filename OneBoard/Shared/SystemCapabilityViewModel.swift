import AppKit
import Foundation
import LaunchAtLogin

protocol SystemPermissionProviding {
    var hasAccessibilityPermission: Bool { get }
    var hasScreenRecordingPermission: Bool { get }
    func showPermissionGuide(for kind: OneBoardPermissionKind)
    func resetAuthorization(for kind: OneBoardPermissionKind) throws
}

protocol GatewayHelperStatusProviding: Sendable {
    func isHelperInstalled() -> Bool
    func installHelper() throws
    func uninstallHelper() throws
}

protocol LaunchAtLoginProviding: AnyObject {
    var isEnabled: Bool { get set }
}

extension PermissionManager: SystemPermissionProviding {
    func showPermissionGuide(for kind: OneBoardPermissionKind) {
        Task { @MainActor in
            PermissionGuideWindowManager.shared.show(for: kind)
        }
    }

    func resetAuthorization(for kind: OneBoardPermissionKind) throws {
        try resetPrivacyAuthorization(for: kind)
    }
}

extension GatewayService: GatewayHelperStatusProviding {}

final class DefaultLaunchAtLoginProvider: LaunchAtLoginProviding {
    var isEnabled: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }
}

@MainActor
final class SystemCapabilityViewModel: ObservableObject {
    static let shared = SystemCapabilityViewModel()

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var gatewayHelperInstalled = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var activePermissionOperation: OneBoardPermissionKind?
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let permissions: SystemPermissionProviding
    private let gatewayHelper: GatewayHelperStatusProviding
    private let launchAtLogin: LaunchAtLoginProviding
    private let confirmsDisablePermission: @MainActor (OneBoardPermissionKind) -> Bool

    init(
        permissions: SystemPermissionProviding = PermissionManager.shared,
        gatewayHelper: GatewayHelperStatusProviding = GatewayService(),
        launchAtLogin: LaunchAtLoginProviding = DefaultLaunchAtLoginProvider(),
        confirmsDisablePermission: @escaping @MainActor (OneBoardPermissionKind) -> Bool = SystemCapabilityViewModel.confirmDisablePermission
    ) {
        self.permissions = permissions
        self.gatewayHelper = gatewayHelper
        self.launchAtLogin = launchAtLogin
        self.confirmsDisablePermission = confirmsDisablePermission
        refresh()
    }

    func refresh() {
        accessibilityGranted = permissions.hasAccessibilityPermission
        screenRecordingGranted = permissions.hasScreenRecordingPermission
        gatewayHelperInstalled = gatewayHelper.isHelperInstalled()
        launchAtLoginEnabled = launchAtLogin.isEnabled
        PermissionManager.shared.syncStoredPermissionStates()
    }

    func setAccessibilityEnabled(_ enabled: Bool) {
        setPermission(.accessibility, enabled: enabled)
    }

    func setScreenRecordingEnabled(_ enabled: Bool) {
        setPermission(.screenRecording, enabled: enabled)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLogin.isEnabled = enabled
        launchAtLoginEnabled = launchAtLogin.isEnabled
        UserDefaults.standard.set(launchAtLoginEnabled, forKey: Constants.UserDefaultsKeys.launchAtLogin)
        if launchAtLoginEnabled != enabled {
            statusMessage = "开机自启未能启用，请确认 OneBoard 位于 /Applications，且登录项 Helper 已正确打包并签名。"
        } else {
            statusMessage = enabled ? "开机自启已启用" : "开机自启已关闭"
        }
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }

    func setGatewayHelperEnabled(_ enabled: Bool) {
        statusMessage = enabled ? "正在安装 OneBoard 网关免密 Helper..." : "正在卸载 OneBoard 网关免密 Helper..."
        Task.detached(priority: .userInitiated) { [gatewayHelper] in
            do {
                if enabled {
                    try gatewayHelper.installHelper()
                } else {
                    try gatewayHelper.uninstallHelper()
                }
                let installed = gatewayHelper.isHelperInstalled()
                await MainActor.run {
                    self.gatewayHelperInstalled = installed
                    self.statusMessage = installed ? "网关免密 Helper 已启用" : "网关免密 Helper 已卸载"
                    self.errorMessage = nil
                    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
                }
            } catch {
                let installed = gatewayHelper.isHelperInstalled()
                await MainActor.run {
                    self.gatewayHelperInstalled = installed
                    self.errorMessage = error.localizedDescription
                    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
                }
            }
        }
    }

    private func setPermission(_ kind: OneBoardPermissionKind, enabled: Bool) {
        activePermissionOperation = kind
        defer { activePermissionOperation = nil }

        if enabled {
            permissions.showPermissionGuide(for: kind)
            refresh()
            schedulePermissionRefresh()
            return
        }

        guard confirmsDisablePermission(kind) else {
            refresh()
            return
        }

        do {
            try permissions.resetAuthorization(for: kind)
            statusMessage = "\(kind.title)授权已关闭"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        schedulePermissionRefresh()
        NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
    }

    private func schedulePermissionRefresh() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            refresh()
            NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
        }
    }

    private static func confirmDisablePermission(_ kind: OneBoardPermissionKind) -> Bool {
        let alert = NSAlert()
        alert.messageText = "关闭\(kind.title)授权？"
        alert.informativeText = "OneBoard 将自动撤销该授权。需要重新使用相关功能时，可以再次打开开关并在系统设置中确认。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭授权")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
