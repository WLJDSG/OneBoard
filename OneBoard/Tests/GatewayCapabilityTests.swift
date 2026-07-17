import XCTest
@testable import OneBoardKit

final class GatewayCapabilityTests: XCTestCase {
    func testOneBoardHelperUsesOneBoardPaths() {
        XCTAssertEqual(OneBoardGatewayHelper.helperPath, "/usr/local/bin/oneboard-gateway-helper")
        XCTAssertEqual(OneBoardGatewayHelper.sudoersPath, "/etc/sudoers.d/oneboard-gateway")
        XCTAssertEqual(OneBoardGatewayHelper.allowedIPsPath, "/etc/oneboard-gateway-allowed-ips.conf")
    }

    func testLegacyHelperWithoutWhitelistSyncIsNotCurrent() {
        XCTAssertFalse(OneBoardGatewayHelper.isCurrentHelperScript("#!/bin/sh\necho legacy"))
        XCTAssertFalse(
            OneBoardGatewayHelper.isCurrentHelperScript(
                "#!/bin/sh\nONEBOARD_GATEWAY_HELPER_VERSION=2\n"
            )
        )
        XCTAssertTrue(
            OneBoardGatewayHelper.isCurrentHelperScript(
                "#!/bin/sh\nONEBOARD_GATEWAY_HELPER_VERSION=3\n"
            )
        )
    }

    func testWhitelistSyncWritesSortedUniqueIPs() throws {
        let runner = RecordingGatewayCommandRunner()
        let helper = OneBoardGatewayHelper(runner: runner)

        try helper.syncWhitelist(ips: ["192.168.31.3", "192.168.31.1", "192.168.31.3"])

        let command = runner.commands.joined(separator: "\n")
        XCTAssertTrue(command.contains("/usr/bin/sudo"))
        XCTAssertTrue(command.contains("-n"))
        XCTAssertTrue(command.contains(OneBoardGatewayHelper.helperPath))
        XCTAssertFalse(command.contains("/usr/bin/osascript"))
        XCTAssertTrue(command.contains("192.168.31.1"))
        XCTAssertTrue(command.contains("192.168.31.3"))
    }

    func testInstallAndInitialWhitelistNeedOnlyOneAuthorization() throws {
        let runner = RecordingGatewayCommandRunner()
        let helper = OneBoardGatewayHelper(runner: runner)

        try helper.install(allowedIPs: ["192.168.31.3", "192.168.31.1"])

        XCTAssertEqual(runner.commands.filter { $0.contains("/usr/bin/osascript") }.count, 1)
        XCTAssertFalse(runner.commands.contains { $0.contains("/usr/bin/sudo") && $0.contains("-n") })
        XCTAssertTrue(runner.commands[0].contains("192.168.31.1"))
        XCTAssertTrue(runner.commands[0].contains("192.168.31.3"))
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
