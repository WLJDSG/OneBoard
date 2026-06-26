import XCTest
@testable import OneBoard

@MainActor
final class SystemCapabilityViewModelTests: XCTestCase {
    func testRefreshReadsAllCapabilityStates() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: false)
        let helper = StubGatewayHelperProvider(installed: true)
        let login = StubLaunchAtLoginProvider(enabled: false)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: helper,
            launchAtLogin: login,
            confirmsDisablePermission: { _ in true }
        )

        viewModel.refresh()

        XCTAssertTrue(viewModel.accessibilityGranted)
        XCTAssertFalse(viewModel.screenRecordingGranted)
        XCTAssertTrue(viewModel.gatewayHelperInstalled)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    func testCancelDisableAccessibilityKeepsRealState() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: StubGatewayHelperProvider(installed: false),
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            confirmsDisablePermission: { _ in false }
        )

        viewModel.setAccessibilityEnabled(false)

        XCTAssertTrue(viewModel.accessibilityGranted)
        XCTAssertEqual(permissions.resetServices, [])
    }

    func testConfirmDisableAccessibilityResetsOnlyAccessibility() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: StubGatewayHelperProvider(installed: false),
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            confirmsDisablePermission: { $0 == .accessibility }
        )

        viewModel.setAccessibilityEnabled(false)

        XCTAssertFalse(viewModel.accessibilityGranted)
        XCTAssertTrue(viewModel.screenRecordingGranted)
        XCTAssertEqual(permissions.resetServices, [.accessibility])
    }

    func testConfirmDisableScreenRecordingResetsOnlyScreenRecording() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: StubGatewayHelperProvider(installed: false),
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            confirmsDisablePermission: { $0 == .screenRecording }
        )

        viewModel.setScreenRecordingEnabled(false)

        XCTAssertTrue(viewModel.accessibilityGranted)
        XCTAssertFalse(viewModel.screenRecordingGranted)
        XCTAssertEqual(permissions.resetServices, [.screenRecording])
        XCTAssertEqual(viewModel.statusMessage, "屏幕录制授权已关闭")
    }

    func testPermissionOperationStateClearsAfterDisable() {
        let permissions = StubPermissionProvider(accessibility: true, screenRecording: true)
        let viewModel = SystemCapabilityViewModel(
            permissions: permissions,
            gatewayHelper: StubGatewayHelperProvider(installed: false),
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            confirmsDisablePermission: { _ in true }
        )

        viewModel.setScreenRecordingEnabled(false)

        XCTAssertNil(viewModel.activePermissionOperation)
    }

    func testLaunchAtLoginFailureShowsInstalledAppGuidance() {
        let login = StubLaunchAtLoginProvider(enabled: false)
        login.forceReadBackValue = false
        let viewModel = SystemCapabilityViewModel(
            permissions: StubPermissionProvider(accessibility: true, screenRecording: true),
            gatewayHelper: StubGatewayHelperProvider(installed: true),
            launchAtLogin: login,
            confirmsDisablePermission: { _ in true }
        )

        viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(viewModel.launchAtLoginEnabled)
        XCTAssertEqual(
            viewModel.statusMessage,
            "开机自启未能启用，请确认 OneBoard 位于 /Applications，且登录项 Helper 已正确打包并签名。"
        )
    }
}

private final class StubPermissionProvider: SystemPermissionProviding {
    var accessibility: Bool
    var screenRecording: Bool
    var resetServices: [OneBoardPermissionKind] = []

    init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    var hasAccessibilityPermission: Bool { accessibility }
    var hasScreenRecordingPermission: Bool { screenRecording }
    var hasInputMonitoringPermission: Bool { true }

    func hasNotificationPermission() async -> Bool { true }

    func showPermissionGuide(for kind: OneBoardPermissionKind) {}

    func resetAuthorization(for kind: OneBoardPermissionKind) throws {
        resetServices.append(kind)
        switch kind {
        case .accessibility:
            accessibility = false
        case .screenRecording:
            screenRecording = false
        case .inputMonitoring, .notifications:
            break
        }
    }
}

private final class StubGatewayHelperProvider: GatewayHelperStatusProviding, @unchecked Sendable {
    var installed: Bool

    init(installed: Bool) {
        self.installed = installed
    }

    func isHelperInstalled() -> Bool { installed }
    func installHelper() throws { installed = true }
    func uninstallHelper() throws { installed = false }
}

private final class StubLaunchAtLoginProvider: LaunchAtLoginProviding {
    var enabled: Bool
    var forceReadBackValue: Bool?

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var isEnabled: Bool {
        get { forceReadBackValue ?? enabled }
        set { enabled = newValue }
    }
}
