import SwiftUI

@MainActor
final class MacStatusWindowManager {
    static let shared = MacStatusWindowManager()
    let card = HoverCardController(title: "Mac 状态", size: CGSize(width: 400, height: 600)) { AnyView(MacStatusView()) }
}

struct MacStatusView: View {
    @ObservedObject private var model = MacStatusModel.shared
    @State private var networkHovered = false
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .memory) }
    var body: some View {
        ScrollView {
        VStack(spacing: 12) {
            HStack {
                Label("Mac 状态", systemImage: "desktopcomputer").font(.system(size: 18, weight: .semibold))
                Spacer(); Label("实时", systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
            }.padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("实时网速").font(.headline); Spacer(); Text("近 60 次采样").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Label(bytes(Int64(model.upload)) + "/s", systemImage: "arrow.up").foregroundStyle(.purple)
                    Spacer()
                    Label(bytes(Int64(model.download)) + "/s", systemImage: "arrow.down").foregroundStyle(.blue)
                }.font(.system(size: 18, weight: .semibold)).monospacedDigit()
                GeometryReader { geometry in
                    let maximum = max(1024, model.history.flatMap { [$0.0, $0.1] }.max() ?? 1024)
                    ForEach(0..<2) { line in
                        Path { path in
                            for (index, sample) in model.history.enumerated() {
                                let point = CGPoint(x: CGFloat(index) / 59 * geometry.size.width, y: geometry.size.height * (1 - (line == 0 ? sample.0 : sample.1) / maximum))
                                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                            }
                        }.stroke(line == 0 ? Color.purple : .blue, lineWidth: 2)
                    }
                }.frame(height: 50)
                Divider()
                Text("应用与进程网络用量").font(.system(size: 12, weight: .semibold))
                ForEach(Array(model.apps.prefix(3))) { app in
                    HStack {
                        Image(nsImage: appIcon(app)).resizable().frame(width: 22, height: 22)
                        Text(app.name).lineLimit(1); Spacer(); Text(bytes(Int64(app.total))).monospacedDigit()
                    }.font(.system(size: 12))
                }
                if model.apps.isEmpty { Text("等待应用产生网络流量").font(.caption).foregroundStyle(.secondary) }
                Text(model.networkStatus).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(14).background(networkHovered ? Color.blue.opacity(0.08) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                .onHover { networkHovered = $0 }
            HStack(spacing: 8) {
                metric("CPU", value: "\(Int(model.cpu * 100))%", progress: model.cpu, color: .blue)
                metric("内存", value: "\(Int(model.memory * 100))%", progress: model.memory, color: .teal)
                metric("温控", value: model.thermal, progress: nil, color: .green)
            }
            Button { openStorage() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label("Macintosh HD", systemImage: "internaldrive"); Spacer(); Text(bytes(model.freeDisk) + " 可用").foregroundStyle(.blue) }.font(.system(size: 12, weight: .semibold))
                coloredProgress(model.totalDisk > 0 ? Double(model.totalDisk - model.freeDisk) / Double(model.totalDisk) : 0, color: .blue)
                Text("总容量 \(bytes(model.totalDisk)) · 内存 \(bytes(Int64(model.usedMemory))) / \(bytes(Int64(ProcessInfo.processInfo.physicalMemory)))").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(14)
            }.buttonStyle(StatusTileStyle()).help("打开系统存储空间设置")
            HStack { Label(model.battery, systemImage: "battery.100percent"); Spacer(); Text("运行 " + MacStatusModel.uptimeText(ProcessInfo.processInfo.systemUptime)) }.font(.system(size: 11)).padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 0)
        }.padding(20)
        }.scrollIndicators(.hidden).frame(width: 400, height: 600)
            .background(Color(nsColor: .windowBackgroundColor))
            .task { model.start() }
    }
    private func appIcon(_ app: AppNetworkUsage) -> NSImage {
        let pid = app.id.split(separator: ".").last.flatMap { Int32($0) }
        return pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: app.name)!
    }
    private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
    private func openStorage() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") else { return }
        NSWorkspace.shared.open(url)
    }
    private func coloredProgress(_ value: Double, color: Color) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, value)))
                }
        }.frame(height: 5)
    }
    private func metric(_ title: String, value: String, progress: Double?, color: Color) -> some View {
        Button { openActivityMonitor() } label: {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: title == "CPU" ? "cpu" : title == "内存" ? "memorychip" : "thermometer.medium").font(.caption).foregroundStyle(color)
            Text(value).font(.system(size: 23, weight: .bold))
            if let progress { coloredProgress(progress, color: color) }
            else { Text("系统状态").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 64).padding(12)
        }.buttonStyle(StatusTileStyle()).help("打开活动监视器")
    }
}

private struct StatusTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration)
    }
    private struct Tile: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .background(hovered ? Color.blue.opacity(0.09) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(hovered ? Color.blue.opacity(0.25) : .clear))
                .opacity(configuration.isPressed ? 0.75 : 1)
                .onHover { hovered = $0 }
        }
    }
}
