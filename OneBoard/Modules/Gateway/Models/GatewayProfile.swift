import Foundation

enum GatewaySwitchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case gatewayAndDNS
    case dnsOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gatewayAndDNS: return "网关 + DNS"
        case .dnsOnly: return "仅 DNS"
        }
    }
}

struct GatewayProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var mode: GatewaySwitchMode
    var gateway: String
    var dnsServers: [String]
    var description: String
    var symbolName: String

    init(
        id: UUID = UUID(),
        title: String,
        mode: GatewaySwitchMode = .gatewayAndDNS,
        gateway: String,
        dnsServers: [String]? = nil,
        description: String,
        symbolName: String = "router"
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.gateway = gateway.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dnsServers = dnsServers ?? [self.gateway]
        self.description = description
        self.symbolName = symbolName
    }

    static let defaults: [GatewayProfile] = [
        GatewayProfile(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            title: "国内网关",
            gateway: "192.168.31.1",
            description: "适合直连国内网络、低延迟访问本地服务。",
            symbolName: "router"
        ),
        GatewayProfile(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")!,
            title: ".2 网关",
            gateway: "192.168.31.2",
            description: "适合切换到 .2 网关，作为备用出口或中间路由。",
            symbolName: "point.3.connected.trianglepath.dotted"
        ),
        GatewayProfile(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")!,
            title: "代理网关",
            gateway: "192.168.31.3",
            description: "适合将默认出口交给旁路由代理。",
            symbolName: "network.badge.shield.half.filled"
        )
    ]

    static func parseDNSServers(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",\n\r\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GatewayError.invalidProfile("标题不能为空")
        }
        if mode == .gatewayAndDNS, !Self.isValidIPv4(gateway) {
            throw GatewayError.invalidGateway(gateway)
        }
        guard !dnsServers.isEmpty else {
            throw GatewayError.invalidProfile("DNS 不能为空")
        }
        for dns in dnsServers where !Self.isValidIPv4(dns) {
            throw GatewayError.invalidDNS(dns)
        }
    }

    static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part), String(number) == part else { return false }
            return (0...255).contains(number)
        }
    }
}

enum GatewayError: LocalizedError, Equatable, Sendable {
    case commandFailed(String)
    case invalidDNS(String)
    case invalidGateway(String)
    case invalidProfile(String)
    case helperRequired
    case missingNetworkConfiguration

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidDNS(let dns):
            return "DNS 地址不合法：\(dns)"
        case .invalidGateway(let gateway):
            return "网关地址不合法：\(gateway)"
        case .invalidProfile(let message):
            return message
        case .helperRequired:
            return "网关 Helper 尚未启用或需要升级，请先在“设置 > 授权”中安装；安装完成后切换只需 Touch ID 或 Mac 登录密码。"
        case .missingNetworkConfiguration:
            return "没有检测到可写入的网络服务、IP 或子网掩码，请先确认当前网络已连接。"
        }
    }
}
