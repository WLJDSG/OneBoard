import XCTest
@testable import OneBoardKit

@MainActor
final class GatewayViewModelAuthorizationTests: XCTestCase {
    func testGatewaySwitchRequestsDeviceOwnerAuthentication() async {
        let authorizer = RecordingSensitiveOperationAuthorizer()
        let viewModel = GatewayViewModel(
            service: GatewayService(runner: RecordingGatewayCommandRunner()),
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
