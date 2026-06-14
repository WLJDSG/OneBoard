import Foundation

final class GatewayService: @unchecked Sendable {
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

    func installHelper() throws {
        try OneBoardGatewayHelper(runner: runner).install()
    }

    func uninstallHelper() throws {
        try OneBoardGatewayHelper(runner: runner).uninstall()
    }
}
