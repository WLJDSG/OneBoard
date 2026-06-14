import XCTest
@testable import OneBoard

final class GatewayProfileTests: XCTestCase {
    func testDefaultProfilesMatchHomeGateways() {
        let profiles = GatewayProfile.defaults

        XCTAssertEqual(profiles.map(\.gateway), ["192.168.31.1", "192.168.31.2", "192.168.31.3"])
        XCTAssertTrue(profiles.allSatisfy { $0.mode == .gatewayAndDNS })
        XCTAssertEqual(profiles[0].dnsServers, ["192.168.31.1"])
    }

    func testParseDNSServersAcceptsCommaWhitespaceAndNewlines() {
        XCTAssertEqual(
            GatewayProfile.parseDNSServers("192.168.31.1, 8.8.8.8\n1.1.1.1"),
            ["192.168.31.1", "8.8.8.8", "1.1.1.1"]
        )
    }

    func testDNSOnlyProfileDoesNotRequireGateway() {
        let profile = GatewayProfile(
            title: "DNS",
            mode: .dnsOnly,
            gateway: "",
            dnsServers: ["1.1.1.1"],
            description: ""
        )

        XCTAssertNoThrow(try profile.validate())
    }

    func testGatewayAndDNSRequiresValidGateway() {
        let profile = GatewayProfile(
            title: "Bad",
            mode: .gatewayAndDNS,
            gateway: "999.1.1.1",
            dnsServers: ["1.1.1.1"],
            description: ""
        )

        XCTAssertThrowsError(try profile.validate())
    }

    func testSnapshotFindsActiveProfileByGateway() {
        let snapshot = NetworkSnapshot(
            gateway: "192.168.31.3",
            interfaceName: "en0",
            serviceName: "Wi-Fi",
            localIPv4: "192.168.31.42",
            subnetMask: "255.255.255.0",
            dnsServers: ["192.168.31.3"]
        )

        XCTAssertEqual(snapshot.activeProfile(from: GatewayProfile.defaults)?.title, "代理网关")
    }
}
