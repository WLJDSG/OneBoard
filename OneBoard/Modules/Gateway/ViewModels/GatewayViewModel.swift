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

    private let service: any GatewayServicing
    private let profileStore: GatewayProfileStore
    private let authorizer: SensitiveOperationAuthorizing
    private var refreshTimer: Timer?

    init(
        service: any GatewayServicing = GatewayService(),
        profileStore: GatewayProfileStore = .shared,
        authorizer: SensitiveOperationAuthorizing = SensitiveOperationAuthorizer()
    ) {
        self.service = service
        self.profileStore = profileStore
        self.authorizer = authorizer
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

    /// 启动网关变化轮询（面板显示时调用）
    func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// 停止网关变化轮询（面板关闭时调用）
    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func switchGateway(to profile: GatewayProfile) {
        guard !isSwitching else { return }
        isSwitching = true
        statusMessage = "正在切换到 \(profile.title)..."

        let ips = Array(Set(whitelistIPs + profile.dnsServers + [profile.gateway])).filter(GatewayProfile.isValidIPv4)
        Task { [service, authorizer] in
            do {
                let installed = await Task.detached { service.isHelperInstalled() }.value
                if !installed {
                    self.statusMessage = "请先授权安装网关 Helper…"
                    try await Task.detached(priority: .userInitiated) {
                        try service.installHelper(allowedIPs: ips)
                    }.value
                    self.isHelperInstalled = await Task.detached { service.isHelperInstalled() }.value
                    guard self.isHelperInstalled else {
                        throw GatewayError.commandFailed("Helper 尚未启用，请完成系统管理员授权后重试")
                    }
                    NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
                }
                self.statusMessage = "请验证身份以切换到 \(profile.title)…"
                try await authorizer.authorize(reason: "确认切换到网关“\(profile.title)”")
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.switchGateway(to: profile, snapshot: service.currentSnapshot())
                    return (service.currentSnapshot(), service.isHelperInstalled())
                }.value
                self.snapshot = result.0
                self.isHelperInstalled = result.1
                self.statusMessage = "已切换到 \(profile.title)"
                self.isSwitching = false
            } catch {
                self.statusMessage = error.localizedDescription
                self.isSwitching = false
                self.refreshHelperStatus()
            }
        }
    }

    func installHelper() {
        statusMessage = "正在安装 OneBoard 网关免密 Helper..."
        let ips = whitelistIPs
        Task.detached(priority: .userInitiated) { [service, ips] in
            do {
                try service.installHelper(allowedIPs: ips)
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
        Task { [service, authorizer] in
            do {
                try await authorizer.authorize(reason: "确认卸载 OneBoard 网关 Helper")
                let installed = try await Task.detached(priority: .userInitiated) {
                    try service.uninstallHelper()
                    return service.isHelperInstalled()
                }.value
                self.isHelperInstalled = installed
                self.statusMessage = "网关免密 Helper 已卸载"
                NotificationCenter.default.post(name: .systemCapabilityStatusDidChange, object: nil)
            } catch {
                self.statusMessage = error.localizedDescription
                self.refreshHelperStatus()
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
