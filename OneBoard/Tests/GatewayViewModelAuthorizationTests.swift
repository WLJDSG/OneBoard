import XCTest
@testable import OneBoardKit

@MainActor
final class GatewayViewModelAuthorizationTests: XCTestCase {
    func testGatewaySwitchRequestsDeviceOwnerAuthentication() async {
        let authorizer = RecordingSensitiveOperationAuthorizer()
        let viewModel = GatewayViewModel(
            service: AuthorizationTestGatewayService(installed: true),
            authorizer: authorizer
        )
        let profile = GatewayProfile(
            title: "公司网络",
            mode: .dnsOnly,
            gateway: "",
            dnsServers: ["1.1.1.1"],
            description: ""
        )

        viewModel.switchGateway(to: profile)
        await waitUntil { !authorizer.reasons.isEmpty }

        XCTAssertEqual(authorizer.reasons, ["确认切换到网关“公司网络”"])
    }

    func testMissingHelperInstallsBeforeFingerprintAndSwitch() async {
        let service = AuthorizationTestGatewayService()
        let authorizer = RecordingSensitiveOperationAuthorizer()
        let viewModel = GatewayViewModel(service: service, authorizer: authorizer)
        let profile = GatewayProfile(title: "测试", mode: .dnsOnly, gateway: "", dnsServers: ["1.1.1.1"], description: "")
        viewModel.switchGateway(to: profile)
        await waitUntil { !viewModel.isSwitching }
        XCTAssertEqual(service.events, ["install", "switch"])
        XCTAssertEqual(authorizer.reasons.count, 1)
        XCTAssertEqual(viewModel.statusMessage, "已切换到 测试")
    }

    func testCancelledHelperInstallDoesNotAuthenticateOrSwitch() async {
        let service = AuthorizationTestGatewayService()
        service.cancelInstall = true
        let authorizer = RecordingSensitiveOperationAuthorizer()
        let viewModel = GatewayViewModel(service: service, authorizer: authorizer)
        let profile = GatewayProfile(title: "测试", mode: .dnsOnly, gateway: "", dnsServers: ["1.1.1.1"], description: "")
        viewModel.switchGateway(to: profile)
        await waitUntil { !viewModel.isSwitching }
        XCTAssertEqual(service.events, ["install"])
        XCTAssertTrue(authorizer.reasons.isEmpty)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class RecordingSensitiveOperationAuthorizer: SensitiveOperationAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReasons: [String] = []

    var reasons: [String] {
        lock.withLock { storedReasons }
    }

    func authorize(reason: String) async throws {
        lock.withLock {
            storedReasons.append(reason)
        }
    }
}

private final class AuthorizationTestGatewayService: GatewayServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var installed = false
    private var storedEvents: [String] = []
    init(installed: Bool = false) { self.installed = installed }
    var cancelInstall = false
    var events: [String] { lock.withLock { storedEvents } }
    func currentSnapshot() -> NetworkSnapshot {
        NetworkSnapshot(gateway: nil, interfaceName: nil, serviceName: "Wi-Fi", localIPv4: nil, dnsServers: [])
    }
    func isHelperInstalled() -> Bool { lock.withLock { installed } }
    func installHelper(allowedIPs: [String]) throws {
        try lock.withLock {
            storedEvents.append("install")
            if cancelInstall { throw GatewayError.commandFailed("用户取消授权") }
            installed = true
        }
    }
    func switchGateway(to profile: GatewayProfile, snapshot: NetworkSnapshot) throws {
        lock.withLock { storedEvents.append("switch") }
    }
    func syncWhitelist(ips: [String]) throws {}
    func uninstallHelper() throws {}
}
