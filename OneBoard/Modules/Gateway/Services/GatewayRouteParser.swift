import Foundation

enum GatewayRouteParser {
    struct DefaultRoute: Equatable {
        var gateway: String?
        var interfaceName: String?
    }

    struct NetworkInfo: Equatable {
        var ipAddress: String?
        var subnetMask: String?
        var router: String?
    }

    static func parseDefaultRoute(_ output: String) -> DefaultRoute {
        var gateway: String?
        var interfaceName: String?

        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "gateway": gateway = parts[1]
            case "interface": interfaceName = parts[1]
            default: break
            }
        }

        return DefaultRoute(gateway: gateway, interfaceName: interfaceName)
    }

    static func parseHardwarePorts(_ output: String) -> [String: String] {
        var servicesByDevice: [String: String] = [:]
        var pendingService: String?

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("Hardware Port:") {
                pendingService = value(afterColonIn: line)
            } else if line.hasPrefix("Device:"), let pendingService {
                let device = value(afterColonIn: line)
                if !device.isEmpty {
                    servicesByDevice[device] = pendingService
                }
            }
        }

        return servicesByDevice
    }

    static func parseNetworkInfo(_ output: String) -> NetworkInfo {
        var info = NetworkInfo()

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("IP address:") {
                info.ipAddress = value(afterColonIn: line)
            } else if line.hasPrefix("Subnet mask:") {
                info.subnetMask = value(afterColonIn: line)
            } else if line.hasPrefix("Router:") {
                info.router = value(afterColonIn: line)
            }
        }

        return info
    }

    static func parseDNSServers(_ output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("There aren't any DNS Servers") else {
            return []
        }
        return trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { GatewayProfile.isValidIPv4($0) }
    }

    private static func value(afterColonIn line: String) -> String {
        line.split(separator: ":", maxSplits: 1)
            .dropFirst()
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
