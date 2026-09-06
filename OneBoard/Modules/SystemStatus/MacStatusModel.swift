import AppKit
import IOKit.ps
import Darwin

struct AppNetworkUsage: Identifiable {
    let id: String
    let name: String
    let received: UInt64
    let sent: UInt64
    var total: UInt64 { received + sent }
}

@MainActor
final class MacStatusModel: ObservableObject {
    static let shared = MacStatusModel()
    @Published var cpu = 0.0
    @Published var memory = 0.0
    @Published var usedMemory: UInt64 = 0
    @Published var upload = 0.0
    @Published var download = 0.0
    @Published var history: [(Double, Double)] = []
    @Published var apps: [AppNetworkUsage] = []
    @Published var networkStatus = "正在采样"
    @Published var freeDisk: Int64 = 0
    @Published var totalDisk: Int64 = 0
    @Published var battery = "无电池信息"
    private var ticks: [UInt64]?
    private var network: (UInt64, UInt64, Date)?
    private var baselines: [String: (UInt64, UInt64)] = [:]
    private var task: Task<Void, Never>?
    init() { sample() }
    static func uptimeText(_ seconds: TimeInterval) -> String {
        let hours = max(0, Int(seconds / 3600))
        return hours >= 24 ? "\(hours / 24) 天 \(hours % 24) 小时" : "\(hours) 小时"
    }
    var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "温热"
        case .serious: return "较热"
        case .critical: return "过热"
        @unknown default: return "未知"
        }
    }
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var count = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.sample()
                if count % 5 == 0 { await self.sampleApps() }
                count += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    private func sample() {
        var cpuInfo = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuCount) }
        }
        if result == KERN_SUCCESS {
            let current = [cpuInfo.cpu_ticks.0, cpuInfo.cpu_ticks.1, cpuInfo.cpu_ticks.2, cpuInfo.cpu_ticks.3].map(UInt64.init)
            if let old = ticks {
                let delta = zip(current, old).map { $0 >= $1 ? $0 - $1 : 0 }
                let total = delta.reduce(0, +)
                if total > 0 { cpu = 1 - Double(delta[2]) / Double(total) }
            }
            ticks = current
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if vmResult == KERN_SUCCESS {
            usedMemory = (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(vm_kernel_page_size)
            memory = min(1, Double(usedMemory) / Double(ProcessInfo.processInfo.physicalMemory))
        }
        var addresses: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addresses) == 0 {
            var incoming: UInt64 = 0; var outgoing: UInt64 = 0
            var pointer = addresses
            while let item = pointer {
                let value = item.pointee
                if value.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), String(cString: value.ifa_name).hasPrefix("en"), let data = value.ifa_data {
                    let counters = data.assumingMemoryBound(to: if_data.self).pointee
                    incoming += UInt64(counters.ifi_ibytes); outgoing += UInt64(counters.ifi_obytes)
                }
                pointer = value.ifa_next
            }
            freeifaddrs(addresses)
            let now = Date()
            if let (oldIn, oldOut, date) = network {
                let elapsed = max(0.1, now.timeIntervalSince(date))
                download = Double(incoming >= oldIn ? incoming - oldIn : 0) / elapsed
                upload = Double(outgoing >= oldOut ? outgoing - oldOut : 0) / elapsed
                history.append((upload, download)); if history.count > 60 { history.removeFirst() }
            }
            network = (incoming, outgoing, now)
        }
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            totalDisk = Int64(values.volumeTotalCapacity ?? 0); freeDisk = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        if totalDisk <= 0 || freeDisk <= 0,
           let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            totalDisk = (attributes[.systemSize] as? NSNumber)?.int64Value ?? totalDisk
            freeDisk = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? freeDisk
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let value = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      let current = value[kIOPSCurrentCapacityKey] as? Int, let maximum = value[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                battery = "电池 \(current * 100 / maximum)% · \((value[kIOPSIsChargingKey] as? Bool) == true ? "正在充电" : "未充电")"
            }
        }
    }
    private func sampleApps() async {
        let output = await Task.detached(priority: .utility) {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            process.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
        var values: [AppNetworkUsage] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, let received = UInt64(fields[1]), let sent = UInt64(fields[2]) else { continue }
            let id = String(fields[0]); let old = baselines[id] ?? (received, sent)
            baselines[id] = old
            let name = id.split(separator: ".").dropLast().joined(separator: ".")
            values.append(AppNetworkUsage(id: id, name: name, received: received >= old.0 ? received - old.0 : 0, sent: sent >= old.1 ? sent - old.1 : 0))
        }
        apps = values.filter { $0.total > 0 }.sorted { $0.total > $1.total }
        networkStatus = output.isEmpty ? "应用用量暂不可用" : "本次采样累计 · 每 5 秒更新"
    }
}
