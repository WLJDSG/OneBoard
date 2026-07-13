import XCTest
@testable import OneBoardKit

@MainActor
final class GatewayProfileEditorViewModelTests: XCTestCase {
    func testBuildProfileParsesMultipleDNSServers() throws {
        let viewModel = GatewayProfileEditorViewModel()
        viewModel.title = "代理"
        viewModel.mode = .gatewayAndDNS
        viewModel.gateway = "192.168.31.3"
        viewModel.dnsText = "192.168.31.3, 8.8.8.8\n1.1.1.1"

        let profile = try viewModel.buildProfile()

        XCTAssertEqual(profile.dnsServers, ["192.168.31.3", "8.8.8.8", "1.1.1.1"])
    }

    func testDNSOnlyBuildsWithoutGateway() throws {
        let viewModel = GatewayProfileEditorViewModel()
        viewModel.title = "只改 DNS"
        viewModel.mode = .dnsOnly
        viewModel.gateway = ""
        viewModel.dnsText = "1.1.1.1"

        let profile = try viewModel.buildProfile()

        XCTAssertEqual(profile.mode, .dnsOnly)
        XCTAssertEqual(profile.gateway, "")
        XCTAssertEqual(profile.dnsServers, ["1.1.1.1"])
    }
}
