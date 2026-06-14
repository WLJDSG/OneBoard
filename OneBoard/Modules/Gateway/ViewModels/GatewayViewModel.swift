import Foundation

@MainActor
final class GatewayViewModel: ObservableObject {
    static let shared = GatewayViewModel()

    @Published private(set) var snapshot = NetworkSnapshot(
        gateway: nil,
        interfaceName: nil,
        serviceName: nil,
        localIPv4: nil,
        dnsServers: []
    )
    @Published private(set) var profiles: [GatewayProfile] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSwitching = false
    @Published private(set) var isHelperInstalled = false
    @Published var statusMessage: String?

    private let service: GatewayService
    private let profileStore: GatewayProfileStore

    init(
        service: GatewayService = GatewayService(),
        profileStore: GatewayProfileStore = .shared
    ) {
        self.service = service
        self.profileStore = profileStore
        loadProfiles()
        refresh()
        refreshHelperStatus()
    }

    var activeProfile: GatewayProfile? {
        snapshot.activeProfile(from: profiles)
    }

    var displayGateway: String {
        activeProfile.map { "\($0.title) \($0.gateway)" }
            ?? snapshot.gateway
            ?? "未知网关"
    }

    var displayService: String {
        [snapshot.serviceName, snapshot.localIPv4]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    func loadProfiles() {
        profiles = profileStore.initializeDefaultsIfNeeded()
    }

    func addProfile(_ profile: GatewayProfile) {
        profileStore.add(profile)
        profiles = profileStore.profiles
        syncWhitelistIfNeeded()
    }

    func updateProfile(_ profile: GatewayProfile) {
        profileStore.update(profile)
        profiles = profileStore.profiles
        syncWhitelistIfNeeded()
    }

    func deleteProfile(id: UUID) {
        profileStore.delete(id: id)
        profiles = profileStore.profiles
        syncWhitelistIfNeeded()
    }

    func refresh() {
        guard !isRefreshing, !isSwitching else { return }
        isRefreshing = true
        Task.detached(priority: .userInitiated) { [service] in
            let nextSnapshot = service.currentSnapshot()
            let helperInstalled = service.isHelperInstalled()
            await MainActor.run {
                self.snapshot = nextSnapshot
                self.isHelperInstalled = helperInstalled
                self.isRefreshing = false
            }
        }
    }

    func refreshHelperStatus() {
        Task.detached(priority: .utility) { [service] in
            let helperInstalled = service.isHelperInstalled()
            await MainActor.run {
                self.isHelperInstalled = helperInstalled
            }
        }
    }

    func switchGateway(to profile: GatewayProfile) {
        guard !isSwitching else { return }
        isSwitching = true
        statusMessage = "正在切换到 \(profile.title)..."

        Task.detached(priority: .userInitiated) { [service, snapshot] in
            do {
                try service.switchGateway(to: profile, snapshot: snapshot)
                let nextSnapshot = service.currentSnapshot()
                let helperInstalled = service.isHelperInstalled()
                await MainActor.run {
                    self.snapshot = nextSnapshot
                    self.isHelperInstalled = helperInstalled
                    self.statusMessage = "已切换到 \(profile.title)"
                    self.isSwitching = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.isSwitching = false
                }
            }
        }
    }

    func installHelper() {
        statusMessage = "正在安装 OneBoard 网关免密 Helper..."
        Task.detached(priority: .userInitiated) { [service] in
            do {
                try service.installHelper()
                let ips = await MainActor.run { self.whitelistIPs }
                try service.syncWhitelist(ips: ips)
                await MainActor.run {
                    self.isHelperInstalled = service.isHelperInstalled()
                    self.statusMessage = "网关免密 Helper 已启用"
                    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.refreshHelperStatus()
                }
            }
        }
    }

    func uninstallHelper() {
        statusMessage = "正在卸载 OneBoard 网关免密 Helper..."
        Task.detached(priority: .userInitiated) { [service] in
            do {
                try service.uninstallHelper()
                await MainActor.run {
                    self.isHelperInstalled = service.isHelperInstalled()
                    self.statusMessage = "网关免密 Helper 已卸载"
                    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.refreshHelperStatus()
                }
            }
        }
    }

    private var whitelistIPs: [String] {
        profiles.map(\.gateway).filter { !$0.isEmpty } + profiles.flatMap(\.dnsServers)
    }

    private func syncWhitelistIfNeeded() {
        guard isHelperInstalled else { return }
        let ips = whitelistIPs
        Task.detached(priority: .utility) { [service, ips] in
            try? service.syncWhitelist(ips: ips)
        }
    }
}
