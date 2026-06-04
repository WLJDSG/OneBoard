import AppKit
import SwiftUI

// MARK: - 权限管理器

final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }
    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    @MainActor func promptAccessibilityPermission() {
        PermissionGuideWindowManager.shared.show(for: .accessibility)
    }

    @MainActor func promptScreenRecordingPermission() {
        PermissionGuideWindowManager.shared.show(for: .screenRecording)
    }

    func openPrivacySetting(for kind: OneBoardPermissionKind) {
        let anchor = (kind == .accessibility) ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        let urlStr = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [urlStr]
        task.launch()
    }
}

// MARK: - 权限流程完成通知

extension Notification.Name {
    static let permissionFlowCompleted = Notification.Name("OneBoardPermissionFlowCompleted")
}

enum OneBoardPermissionKind {
    case accessibility
    case screenRecording

    var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        }
    }
}

// MARK: - 权限引导窗口管理

@MainActor
final class PermissionGuideWindowManager {
    static let shared = PermissionGuideWindowManager()

    private var panel: NSPanel?
    private var timer: Timer?
    private var currentKind: OneBoardPermissionKind?
    private var isRevoke: Bool = false
    private var flowStartTime: Date = Date()  // 最短保护期，防权限 API 缓存误判

    var hasActiveFlow: Bool { currentKind != nil }

    private init() {}

    func show(for kind: OneBoardPermissionKind, revokeMode: Bool = false) {
        // 先清理上一个流程
        hide()

        currentKind = kind
        isRevoke = revokeMode
        flowStartTime = Date()  // 重置保护期

        // 打开系统设置
        PermissionManager.shared.openPrivacySetting(for: kind)

        // revoke 模式：只开系统设置 + 轮询，不显示引导窗
        if revokeMode {
            startPolling()
            return
        }

        // 授权模式：显示引导悬浮窗
        showGuidePanel(kind: kind)
        startPolling()
    }

    private func showGuidePanel(kind: OneBoardPermissionKind) {
        let view = NSHostingView(rootView: PermissionGuideView(kind: kind) { [weak self] in
            self?.hide()
        })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 118),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = view
        FloatingWindowManager.positionAtTopRight(panel, offset: 28)
        panel.makeKeyAndOrderFront(nil)

        self.panel?.close()
        self.panel = panel
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        currentKind = nil
        isRevoke = false
    }

    // MARK: - 轮询

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
    }

    private func checkPermission() {
        guard let kind = currentKind else { return }

        // 最短保护期 1.5s：防止 AXIsProcessTrusted / CGPreflightScreenCaptureAccess 返回缓存值
        // 导致流程刚启动就被误判为「已完成」而关闭悬浮框
        guard Date().timeIntervalSince(flowStartTime) > 1.5 else { return }

        let granted: Bool
        switch kind {
        case .accessibility:    granted = PermissionManager.shared.hasAccessibilityPermission
        case .screenRecording:  granted = PermissionManager.shared.hasScreenRecordingPermission
        }

        let completed = isRevoke ? !granted : granted
        guard completed else { return }

        // revoke 模式还需要等用户关闭系统设置
        if isRevoke && isSystemSettingsRunning() { return }

        finishFlow()
    }

    private func finishFlow() {
        hide()

        // 恢复设置窗口 + 通知刷新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            SettingsWindowManager.shared.bringToFront()
            NotificationCenter.default.post(name: .permissionFlowCompleted, object: nil)
        }
    }

    private func isSystemSettingsRunning() -> Bool {
        let ids = ["com.apple.SystemSettings", "com.apple.systempreferences"]
        return NSWorkspace.shared.runningApplications.contains { ids.contains($0.bundleIdentifier ?? "") }
    }
}

// MARK: - 权限引导视图

private struct PermissionGuideView: View {
    let kind: OneBoardPermissionKind
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 48, height: 48)
                .shadow(radius: 4, y: 2)
                .onDrag {
                    NSItemProvider(object: Bundle.main.bundleURL as NSURL)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("开启 \(kind.title)")
                    .font(.system(size: 13, weight: .semibold))
                Text(kind == .accessibility
                    ? "把 OneBoard 拖到右侧列表，打开开关"
                    : "把 OneBoard 拖到右侧列表，打开开关后重启 App")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开设置") {
                    PermissionManager.shared.openPrivacySetting(for: kind)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 250, height: 118)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}
