import XCTest
@testable import OneBoardKit

final class GatewaySwitcherTests: XCTestCase {
    func testGatewayPanelUsesCompactSize() {
        XCTAssertEqual(GatewaySwitcherPanelLayout.size, CGSize(width: 380, height: 440))
    }

    func testParseDefaultRouteAndHardwarePorts() {
        let route = GatewayRouteParser.parseDefaultRoute("""
           route to: default
        destination: default
               mask: default
            gateway: 192.168.31.1
          interface: en0
        """)

        XCTAssertEqual(route.gateway, "192.168.31.1")
        XCTAssertEqual(route.interfaceName, "en0")

        let ports = GatewayRouteParser.parseHardwarePorts("""
        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: aa:bb
        """)

        XCTAssertEqual(ports["en0"], "Wi-Fi")
    }

    func testParseNetworkInfoAndDNSServers() {
        let info = GatewayRouteParser.parseNetworkInfo("""
        IP address: 192.168.31.42
        Subnet mask: 255.255.255.0
        Router: 192.168.31.1
        """)

        XCTAssertEqual(info.ipAddress, "192.168.31.42")
        XCTAssertEqual(info.subnetMask, "255.255.255.0")
        XCTAssertEqual(info.router, "192.168.31.1")

        XCTAssertEqual(
            GatewayRouteParser.parseDNSServers("192.168.31.1\n8.8.8.8\n"),
            ["192.168.31.1", "8.8.8.8"]
        )
        XCTAssertEqual(GatewayRouteParser.parseDNSServers("There aren't any DNS Servers set on Wi-Fi."), [])
    }

    func testGatewayAndDNSUsesManualRouteAndDNSCommands() throws {
        let runner = RecordingGatewayCommandRunner()
        let switcher = GatewaySwitcher(runner: runner)
        let profile = GatewayProfile(title: "代理网关", gateway: "192.168.31.3", description: "")
        let snapshot = NetworkSnapshot(
            gateway: "192.168.31.1",
            interfaceName: "en0",
            serviceName: "Wi-Fi",
            localIPv4: "192.168.31.42",
            subnetMask: "255.255.255.0",
            dnsServers: []
        )

        try switcher.switchDefaultGateway(to: profile, snapshot: snapshot)

        let script = runner.commands.joined(separator: "\n")
        XCTAssertTrue(script.contains(OneBoardGatewayHelper.helperPath))
        XCTAssertTrue(script.contains("--ip"))
        XCTAssertTrue(script.contains("--subnet"))
        XCTAssertTrue(script.contains("--router"))
        XCTAssertTrue(script.contains("192.168.31.42"))
        XCTAssertTrue(script.contains("192.168.31.3"))
        XCTAssertTrue(script.contains("--dns"))
    }

    func testDNSOnlyDoesNotChangeDefaultRoute() throws {
        let runner = RecordingGatewayCommandRunner()
        let switcher = GatewaySwitcher(runner: runner)
        let profile = GatewayProfile(
            title: "DNS",
            mode: .dnsOnly,
            gateway: "",
            dnsServers: ["1.1.1.1"],
            description: ""
        )
        let snapshot = NetworkSnapshot(
            gateway: "192.168.31.1",
            interfaceName: "en0",
            serviceName: "Wi-Fi",
            localIPv4: "192.168.31.42",
            subnetMask: "255.255.255.0",
            dnsServers: []
        )

        try switcher.switchDefaultGateway(to: profile, snapshot: snapshot)

        let script = runner.commands.joined(separator: "\n")
        XCTAssertTrue(script.contains(OneBoardGatewayHelper.helperPath))
        XCTAssertFalse(script.contains("--ip"))
        XCTAssertFalse(script.contains("--subnet"))
        XCTAssertFalse(script.contains("--router"))
        XCTAssertTrue(script.contains("--dns"))
        XCTAssertTrue(script.contains("1.1.1.1"))
    }

    func testHelperBusinessRejectionNeverFallsBackToPasswordPrompt() {
        let runner = RecordingGatewayCommandRunner(results: [
            GatewayCommandResult(
                standardOutput: "",
                standardError: "DNS is not allowed: 1.1.1.1",
                terminationStatus: 3
            )
        ])
        let switcher = GatewaySwitcher(runner: runner)
        let profile = GatewayProfile(
            title: "DNS",
            mode: .dnsOnly,
            gateway: "",
            dnsServers: ["1.1.1.1"],
            description: ""
        )
        let snapshot = NetworkSnapshot(
            gateway: "192.168.31.1",
            interfaceName: "en0",
            serviceName: "Wi-Fi",
            localIPv4: "192.168.31.42",
            subnetMask: "255.255.255.0",
            dnsServers: []
        )

        XCTAssertThrowsError(try switcher.switchDefaultGateway(to: profile, snapshot: snapshot))
        XCTAssertFalse(runner.commands.contains { $0.contains("/usr/bin/osascript") })
    }

    func testMissingHelperRequiresInstallationInsteadOfPasswordPrompt() {
        let runner = RecordingGatewayCommandRunner(results: [
            GatewayCommandResult(
                standardOutput: "",
                standardError: "sudo: a password is required",
                terminationStatus: 1
            )
        ])
        let switcher = GatewaySwitcher(runner: runner)
        let profile = GatewayProfile(
            title: "DNS",
            mode: .dnsOnly,
            gateway: "",
            dnsServers: ["1.1.1.1"],
            description: ""
        )
        let snapshot = NetworkSnapshot(
            gateway: "192.168.31.1",
            interfaceName: "en0",
            serviceName: "Wi-Fi",
            localIPv4: "192.168.31.42",
            subnetMask: "255.255.255.0",
            dnsServers: []
        )

        XCTAssertThrowsError(try switcher.switchDefaultGateway(to: profile, snapshot: snapshot)) { error in
            XCTAssertEqual(error as? GatewayError, .helperRequired)
        }
        XCTAssertFalse(runner.commands.contains { $0.contains("/usr/bin/osascript") })
    }
}
