import Foundation

@MainActor
final class GatewayProfileEditorViewModel: ObservableObject {
    @Published var title: String
    @Published var mode: GatewaySwitchMode
    @Published var gateway: String
    @Published var dnsText: String
    @Published var description: String
    @Published var symbolName: String

    private let editingID: UUID?

    init(profile: GatewayProfile? = nil) {
        self.editingID = profile?.id
        self.title = profile?.title ?? ""
        self.mode = profile?.mode ?? .gatewayAndDNS
        self.gateway = profile?.gateway ?? ""
        self.dnsText = profile?.dnsServers.joined(separator: "\n") ?? ""
        self.description = profile?.description ?? ""
        self.symbolName = profile?.symbolName ?? "router"
    }

    func buildProfile() throws -> GatewayProfile {
        let parsedDNS = GatewayProfile.parseDNSServers(dnsText)
        let profile = GatewayProfile(
            id: editingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            gateway: gateway.trimmingCharacters(in: .whitespacesAndNewlines),
            dnsServers: parsedDNS,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "router" : symbolName
        )
        try profile.validate()
        return profile
    }
}
