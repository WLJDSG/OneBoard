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

    func showPermissionGuide(for kind: OneBoardPermissionKind) {}

    func resetAuthorization(for kind: OneBoardPermissionKind) throws {
        resetServices.append(kind)
        switch kind {
        case .accessibility:
            accessibility = false
        case .screenRecording:
            screenRecording = false
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

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var isEnabled: Bool {
        get { enabled }
        set { enabled = newValue }
    }
}
