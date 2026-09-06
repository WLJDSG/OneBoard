import Foundation

protocol GatewayServicing: Sendable {
    func currentSnapshot() -> NetworkSnapshot
    func switchGateway(to profile: GatewayProfile, snapshot: NetworkSnapshot) throws
    func isHelperInstalled() -> Bool
    func syncWhitelist(ips: [String]) throws
    func installHelper(allowedIPs: [String]) throws
    func uninstallHelper() throws
}

final class GatewayService: GatewayServicing, @unchecked Sendable {
    private let runner: GatewayCommandRunning

    init(runner: GatewayCommandRunning = ProcessGatewayCommandRunner()) {
        self.runner = runner
    }

    func currentSnapshot() -> NetworkSnapshot {
        NetworkInspector(runner: runner).snapshot()
    }

    func switchGateway(to profile: GatewayProfile, snapshot: NetworkSnapshot) throws {
        try GatewaySwitcher(runner: runner).switchDefaultGateway(to: profile, snapshot: snapshot)
    }

    func isHelperInstalled() -> Bool {
        OneBoardGatewayHelper(runner: runner).isInstalled()
    }

    func syncWhitelist(ips: [String]) throws {
        try OneBoardGatewayHelper(runner: runner).syncWhitelist(ips: ips)
    }

    func installHelper(allowedIPs: [String]) throws {
        try OneBoardGatewayHelper(runner: runner).install(allowedIPs: allowedIPs)
    }

    func installHelper() throws {
        let profiles = GatewayProfileStore.shared.initializeDefaultsIfNeeded()
        let allowedIPs = profiles.map(\.gateway).filter { !$0.isEmpty }
            + profiles.flatMap(\.dnsServers)
        try installHelper(allowedIPs: allowedIPs)
    }

    func uninstallHelper() throws {
        try OneBoardGatewayHelper(runner: runner).uninstall()
    }
}
