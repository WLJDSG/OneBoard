import Foundation

struct GatewaySwitcher {
    private let runner: GatewayCommandRunning

    init(runner: GatewayCommandRunning = ProcessGatewayCommandRunner()) {
        self.runner = runner
    }

    func switchDefaultGateway(to profile: GatewayProfile) throws {
        try switchDefaultGateway(to: profile, snapshot: NetworkInspector(runner: runner).snapshot())
    }

    func switchDefaultGateway(to profile: GatewayProfile, snapshot: NetworkSnapshot) throws {
        try profile.validate()
        guard let serviceName = snapshot.serviceName else {
            throw GatewayError.missingNetworkConfiguration
        }

        guard try runPasswordlessHelper(profile: profile, serviceName: serviceName, snapshot: snapshot) else {
            throw GatewayError.helperRequired
        }
    }

    private func runPasswordlessHelper(
        profile: GatewayProfile,
        serviceName: String,
        snapshot: NetworkSnapshot
    ) throws -> Bool {
        var arguments = [
            "-n",
            OneBoardGatewayHelper.helperPath,
            "--service", serviceName,
            "--dns", profile.dnsServers.joined(separator: ",")
        ]
        if profile.mode == .gatewayAndDNS {
            guard let ipAddress = snapshot.localIPv4, let subnetMask = snapshot.subnetMask else {
                throw GatewayError.missingNetworkConfiguration
            }
            arguments += ["--ip", ipAddress, "--subnet", subnetMask, "--router", profile.gateway]
        }

        let result = try runner.run("/usr/bin/sudo", arguments: arguments)
        if result.terminationStatus == 0 { return true }

        let combinedOutput = "\(result.standardError)\n\(result.standardOutput)"
        if combinedOutput.contains("a password is required")
            || combinedOutput.contains("no tty present")
            || combinedOutput.contains("command not found")
            || combinedOutput.contains("No such file") {
            return false
        }

        throw GatewayError.commandFailed(combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

}
