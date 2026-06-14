import Darwin
import Foundation

struct NetworkInspector {
    private let runner: GatewayCommandRunning

    init(runner: GatewayCommandRunning = ProcessGatewayCommandRunner()) {
        self.runner = runner
    }

    func snapshot() -> NetworkSnapshot {
        let routeOutput = (try? runner.run("/sbin/route", arguments: ["-n", "get", "default"]).standardOutput) ?? ""
        let route = GatewayRouteParser.parseDefaultRoute(routeOutput)

        let servicesOutput = (try? runner.run("/usr/sbin/networksetup", arguments: ["-listallhardwareports"]).standardOutput) ?? ""
        let servicesByDevice = GatewayRouteParser.parseHardwarePorts(servicesOutput)
        let serviceName = route.interfaceName.flatMap { servicesByDevice[$0] }

        let networkInfo = serviceName.flatMap { service in
            try? runner.run("/usr/sbin/networksetup", arguments: ["-getinfo", service]).standardOutput
        }.map(GatewayRouteParser.parseNetworkInfo)

        let interfaceIPv4 = route.interfaceName.flatMap { localIPv4Configuration(for: $0) }
        let localIP = networkInfo?.ipAddress ?? interfaceIPv4?.ipAddress
        let subnetMask = networkInfo?.subnetMask ?? interfaceIPv4?.subnetMask
        let gateway = networkInfo?.router ?? route.gateway
        let dnsServers = serviceName.flatMap { service in
            try? runner.run("/usr/sbin/networksetup", arguments: ["-getdnsservers", service]).standardOutput
        }.map(GatewayRouteParser.parseDNSServers) ?? []

        return NetworkSnapshot(
            gateway: gateway,
            interfaceName: route.interfaceName,
            serviceName: serviceName,
            localIPv4: localIP,
            subnetMask: subnetMask,
            dnsServers: dnsServers
        )
    }

    private func localIPv4Configuration(for interfaceName: String) -> (ipAddress: String, subnetMask: String?)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let pointer = cursor {
            defer { cursor = pointer.pointee.ifa_next }

            let interface = String(cString: pointer.pointee.ifa_name)
            guard interface == interfaceName else { continue }
            guard pointer.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                pointer.pointee.ifa_addr,
                socklen_t(pointer.pointee.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let subnetMask = pointer.pointee.ifa_netmask.flatMap { sockaddrToIPv4($0) }
                return (String(cString: hostname), subnetMask)
            }
        }

        return nil
    }

    private func sockaddrToIPv4(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        guard address.pointee.sa_family == UInt8(AF_INET) else { return nil }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )

        guard result == 0 else { return nil }
        return String(cString: hostname)
    }
}
