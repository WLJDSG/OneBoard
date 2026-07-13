import XCTest
@testable import OneBoardKit

final class GatewayCapabilityTests: XCTestCase {
    func testOneBoardHelperUsesOneBoardPaths() {
        XCTAssertEqual(OneBoardGatewayHelper.helperPath, "/usr/local/bin/oneboard-gateway-helper")
        XCTAssertEqual(OneBoardGatewayHelper.sudoersPath, "/etc/sudoers.d/oneboard-gateway")
        XCTAssertEqual(OneBoardGatewayHelper.allowedIPsPath, "/etc/oneboard-gateway-allowed-ips.conf")
    }

    func testWhitelistSyncWritesSortedUniqueIPs() throws {
        let runner = RecordingGatewayCommandRunner()
        let helper = OneBoardGatewayHelper(runner: runner)

        try helper.syncWhitelist(ips: ["192.168.31.3", "192.168.31.1", "192.168.31.3"])

        let command = runner.commands.joined(separator: "\n")
        XCTAssertTrue(command.contains("192.168.31.1"))
        XCTAssertTrue(command.contains("192.168.31.3"))
        XCTAssertTrue(command.contains(OneBoardGatewayHelper.allowedIPsPath))
    }

    func testUninstallRemovesHelperSudoersAndWhitelist() throws {
        let runner = RecordingGatewayCommandRunner()
        let helper = OneBoardGatewayHelper(runner: runner)

        try helper.uninstall()

        let command = runner.commands.joined(separator: "\n")
        XCTAssertTrue(command.contains(OneBoardGatewayHelper.helperPath))
        XCTAssertTrue(command.contains(OneBoardGatewayHelper.sudoersPath))
        XCTAssertTrue(command.contains(OneBoardGatewayHelper.allowedIPsPath))
    }
}
