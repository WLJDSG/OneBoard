import Foundation

struct NetworkSnapshot: Equatable, Sendable {
    var gateway: String?
    var interfaceName: String?
    var serviceName: String?
    var localIPv4: String?
    var subnetMask: String?
    var dnsServers: [String]
    var capturedAt: Date

    init(
        gateway: String?,
        interfaceName: String?,
        serviceName: String?,
        localIPv4: String?,
        subnetMask: String? = nil,
        dnsServers: [String],
        capturedAt: Date = Date()
    ) {
        self.gateway = gateway
        self.interfaceName = interfaceName
        self.serviceName = serviceName
        self.localIPv4 = localIPv4
        self.subnetMask = subnetMask
        self.dnsServers = dnsServers
        self.capturedAt = capturedAt
    }

    func activeProfile(from profiles: [GatewayProfile]) -> GatewayProfile? {
        guard let gateway else { return nil }
        return profiles.first { $0.mode == .gatewayAndDNS && $0.gateway == gateway }
    }
}
