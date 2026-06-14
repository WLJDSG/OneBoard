import Foundation

struct GatewayHelperConfiguration {
    var isEnabled: Bool

    static let disabledForTests = GatewayHelperConfiguration(isEnabled: false)
    static let system = GatewayHelperConfiguration(isEnabled: true)
}

struct GatewaySwitcher {
    private let runner: GatewayCommandRunning
    private let helper: GatewayHelperConfiguration

    init(
        runner: GatewayCommandRunning = ProcessGatewayCommandRunner(),
        helper: GatewayHelperConfiguration = .system
    ) {
        self.runner = runner
        self.helper = helper
    }

    func switchDefaultGateway(to profile: GatewayProfile) throws {
        try switchDefaultGateway(to: profile, snapshot: NetworkInspector(runner: runner).snapshot())
    }

    func switchDefaultGateway(to profile: GatewayProfile, snapshot: NetworkSnapshot) throws {
        try profile.validate()
        guard let serviceName = snapshot.serviceName else {
            throw GatewayError.missingNetworkConfiguration
        }

        if helper.isEnabled, try runPasswordlessHelper(profile: profile, serviceName: serviceName, snapshot: snapshot) {
            return
        }

        let shellCommand = Self.shellCommand(serviceName: serviceName, profile: profile, snapshot: snapshot)
        let appleScript = "do shell script \(shellCommand.appleScriptQuoted) with administrator privileges"
        let result = try runner.run("/usr/bin/osascript", arguments: ["-e", appleScript])
        guard result.terminationStatus == 0 else {
            throw GatewayError.commandFailed(Self.failureMessage(from: result))
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
            || combinedOutput.contains("No such file")
            || combinedOutput.contains("not allowed") {
            return false
        }

        throw GatewayError.commandFailed(combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func shellCommand(
        serviceName: String,
        profile: GatewayProfile,
        snapshot: NetworkSnapshot
    ) -> String {
        let service = serviceName.shellQuoted
        let dns = profile.dnsServers.map(\.shellQuoted).joined(separator: " ")
        var commands: [String] = []

        if profile.mode == .gatewayAndDNS {
            guard let ipAddress = snapshot.localIPv4, let subnetMask = snapshot.subnetMask else {
                return "exit 2"
            }
            commands.append("/usr/sbin/networksetup -setmanual \(service) \(ipAddress.shellQuoted) \(subnetMask.shellQuoted) \(profile.gateway.shellQuoted)")
        }

        commands.append("/usr/sbin/networksetup -setdnsservers \(service) \(dns)")

        if profile.mode == .gatewayAndDNS {
            commands.append("/sbin/route -n change default \(profile.gateway.shellQuoted) || /sbin/route -n add default \(profile.gateway.shellQuoted)")
        }

        commands.append("/usr/bin/dscacheutil -flushcache")
        commands.append("/usr/bin/killall -HUP mDNSResponder || true")
        return commands.joined(separator: "; ")
    }

    private static func failureMessage(from result: GatewayCommandResult) -> String {
        [result.standardError, result.standardOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "切换网关失败"
    }
}
