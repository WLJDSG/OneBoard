import XCTest
@testable import OneBoardKit

@MainActor
final class SystemCapabilityViewModelTests: XCTestCase {
    func testSettingsInitializationNeverRunsHelperProbeOnMainThread() async {
        let helper = BackgroundProbeHelper()
        let model = SystemCapabilityViewModel(
            permissions: StubPermissionProvider(accessibility: true, screenRecording: true),
            gatewayHelper: helper, launchAtLogin: StubLaunchAtLoginProvider(enabled: false))
        await waitUntil { model.gatewayHelperInstalled }
        XCTAssertTrue(model.gatewayHelperInstalled)
        XCTAssertFalse(helper.calledOnMainThread)
    }

    func testExplicitQuitDoesNotSchedulePermissionRelaunch() {
        let delegate = AppDelegate()
        delegate.prepareForUserTermination()
        XCTAssertFalse(delegate.shouldRelaunchAfterTermination)
    }

    func testRefreshReadsAllCapabilityStates() async {
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
        await waitUntil { viewModel.gatewayHelperInstalled }

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

    func testDisablingGatewayHelperRequiresAuthentication() async {
        let helper = StubGatewayHelperProvider(installed: true)
        let authorizer = StubSensitiveOperationAuthorizer()
        let viewModel = SystemCapabilityViewModel(
            permissions: StubPermissionProvider(accessibility: true, screenRecording: true),
            gatewayHelper: helper,
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            authorizer: authorizer,
            confirmsDisablePermission: { _ in true }
        )

        viewModel.setGatewayHelperEnabled(false)
        await waitUntil { !helper.installed }

        XCTAssertEqual(authorizer.reasons, ["确认卸载 OneBoard 网关 Helper"])
        XCTAssertFalse(helper.installed)
    }

    func testFailedAuthenticationKeepsGatewayHelperInstalled() async {
        let helper = StubGatewayHelperProvider(installed: true)
        let authorizer = StubSensitiveOperationAuthorizer(error: SensitiveOperationAuthorizationError.failed("用户取消"))
        let viewModel = SystemCapabilityViewModel(
            permissions: StubPermissionProvider(accessibility: true, screenRecording: true),
            gatewayHelper: helper,
            launchAtLogin: StubLaunchAtLoginProvider(enabled: false),
            authorizer: authorizer,
            confirmsDisablePermission: { _ in true }
        )

        viewModel.setGatewayHelperEnabled(false)
        await waitUntil { viewModel.errorMessage != nil }

        XCTAssertTrue(helper.installed)
        XCTAssertEqual(viewModel.errorMessage, "身份验证未通过：用户取消")
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
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

    func hasNotificationPermission() async -> Bool { true }

    func showPermissionGuide(for kind: OneBoardPermissionKind) {}

    func resetAuthorization(for kind: OneBoardPermissionKind) throws {
        resetServices.append(kind)
        switch kind {
        case .accessibility:
            accessibility = false
        case .screenRecording:
            screenRecording = false
        case .notifications:
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

private final class StubSensitiveOperationAuthorizer: SensitiveOperationAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReasons: [String] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    var reasons: [String] {
        lock.withLock { storedReasons }
    }

    func authorize(reason: String) async throws {
        lock.withLock {
            storedReasons.append(reason)
        }
        if let error {
            throw error
        }
    }
}

private final class BackgroundProbeHelper: GatewayHelperStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var mainThread = false
    var calledOnMainThread: Bool { lock.withLock { mainThread } }
    func isHelperInstalled() -> Bool {
        lock.withLock { mainThread = mainThread || Thread.isMainThread }
        return true
    }
    func installHelper() throws {}
    func uninstallHelper() throws {}
}
