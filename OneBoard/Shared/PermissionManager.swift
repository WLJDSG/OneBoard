import AppKit
import SwiftUI

/// 权限管理器
final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    // MARK: - 辅助功能权限

    /// 检查辅助功能权限
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        openAccessibilitySettings()
    }

    // MARK: - 屏幕录制权限

    /// 检查屏幕录制权限
    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    // MARK: - 权限引导

    /// 检查所有必要权限，返回缺失的权限列表
    var missingPermissions: [String] {
        var missing: [String] = []
        if !hasAccessibilityPermission {
            missing.append("辅助功能")
        }
        return missing
    }

    /// 打开权限引导
    @MainActor
    func promptAccessibilityPermission() {
        openAccessibilitySettings()
        PermissionGuideWindowManager.shared.show(for: .accessibility)
    }

    /// 打开系统设置的对应权限页面（macOS 14+ 适配）
    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    /// 使用 Process 打开系统设置，兼容 macOS 14+ URL 格式变化
    private func openPrivacySettings(anchor: String) {
        // macOS 14+ 的 URL scheme 发生了变化，使用 Process 调 open 命令更可靠
        let urlStr = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [urlStr]
        task.launch()
        // 不等待退出，fire-and-forget
    }

    /// 根据权限类型打开系统设置
    func openPrivacySetting(for kind: OneBoardPermissionKind) {
        switch kind {
        case .accessibility:
            openAccessibilitySettings()
        case .screenRecording:
            openScreenRecordingSettings()
        }
    }

    /// 打开屏幕录制权限页并显示拖拽引导
    @MainActor
    func promptScreenRecordingPermission() {
        openScreenRecordingSettings()
        PermissionGuideWindowManager.shared.show(for: .screenRecording)
    }
}

/// 权限流程完成通知
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

    var instruction: String {
        switch self {
        case .accessibility:
            return "把 OneBoard 拖到右侧列表，打开开关"
        case .screenRecording:
            return "把 OneBoard 拖到右侧列表，打开开关后重启 App"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }
}

@MainActor
final class PermissionGuideWindowManager {
    static let shared = PermissionGuideWindowManager()

    private var panel: NSPanel?
    private var timer: Timer?
    private var currentKind: OneBoardPermissionKind?
    private var revokeMode: Bool = false
    private var generation: Int = 0          // 每次 show() 递增，防止过期 finishFlow 执行
    private var flowStartTime: Date = Date()  // 最短轮询延迟，避免权限状态缓存导致的误判

    var hasActiveFlow: Bool {
        currentKind != nil
    }

    private init() {}

    func show(for kind: OneBoardPermissionKind, revokeMode: Bool = false) {
        // 取消上一个流程的延迟回调
        generation += 1
        let currentGen = generation

        self.currentKind = kind
        self.revokeMode = revokeMode
        self.flowStartTime = Date()

        // revoke 模式：只打开系统设置，不显示悬浮引导窗口
        if revokeMode {
            panel?.close()
            panel = nil
            openSettingsAndPoll(currentGen: currentGen, kind: kind)
            return
        }

        // 授权模式：先显示引导悬浮窗，再打开系统设置
        let view = NSHostingView(rootView: PermissionGuideView(kind: kind, revokeMode: revokeMode) { [weak self] in
            self?.hide()
        })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 118),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
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

        openSettingsAndPoll(currentGen: currentGen, kind: kind)
    }

    /// 打开系统设置 + 启动轮询
    private func openSettingsAndPoll(currentGen: Int, kind: OneBoardPermissionKind) {
        // 先显示引导窗口（确保用户能看到），再打开系统设置
        // 系统设置打开可能失败（URL 格式问题），但引导窗口已经在屏幕上
        PermissionManager.shared.openPrivacySetting(for: kind)
        startPermissionPolling(currentGen: currentGen)
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        currentKind = nil
        revokeMode = false
    }

    private func startPermissionPolling(currentGen: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let kind = self.currentKind,
                      self.generation == currentGen  // 过期流程忽略
                else { return }

                // 最短延迟：防止权限状态 API 返回缓存值导致误判
                guard Date().timeIntervalSince(self.flowStartTime) > 1.5 else { return }

                let completed: Bool
                switch kind {
                case .accessibility:
                    completed = self.revokeMode
                        ? !PermissionManager.shared.hasAccessibilityPermission
                        : PermissionManager.shared.hasAccessibilityPermission
                case .screenRecording:
                    completed = self.revokeMode
                        ? !PermissionManager.shared.hasScreenRecordingPermission
                        : PermissionManager.shared.hasScreenRecordingPermission
                }

                if completed {
                    if self.revokeMode {
                        if !self.isSystemSettingsRunning() {
                            self.finishFlow(currentGen: currentGen)
                        }
                    } else {
                        self.finishFlow(currentGen: currentGen)
                    }
                }
            }
        }
    }

    private func finishFlow(currentGen: Int) {
        // 再次检查 generation，防止过期调用
        guard generation == currentGen else { return }

        if !revokeMode {
            closeSystemSettings()
        }

        let wasRevokeMode = revokeMode
        hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // revoke 模式下设置窗口本来就开着，不需要强制 show()
            if !wasRevokeMode {
                SettingsWindowManager.shared.show()
            }
            NotificationCenter.default.post(name: .permissionFlowCompleted, object: nil)
        }
    }

    private func isSystemSettingsRunning() -> Bool {
        let ids = ["com.apple.SystemSettings", "com.apple.systempreferences"]
        return NSWorkspace.shared.runningApplications.contains { app in
            ids.contains(app.bundleIdentifier ?? "")
        }
    }

    private func closeSystemSettings() {
        let ids = ["com.apple.SystemSettings", "com.apple.systempreferences"]
        for app in NSWorkspace.shared.runningApplications where ids.contains(app.bundleIdentifier ?? "") {
            app.terminate()
        }
    }
}

private struct PermissionGuideView: View {
    let kind: OneBoardPermissionKind
    let revokeMode: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            appDragSource

            VStack(alignment: .leading, spacing: 6) {
                Text(revokeMode ? "移除 \(kind.title)" : "开启 \(kind.title)")
                    .font(.system(size: 13, weight: .semibold))
                Text(revokeMode ? "macOS 需要你在系统设置里手动关闭权限。" : kind.instruction)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开设置") {
                    NSWorkspace.shared.open(kind.settingsURL)
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

    private var appDragSource: some View {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return Image(nsImage: icon)
            .resizable()
            .frame(width: 48, height: 48)
            .shadow(radius: 4, y: 2)
            .onDrag {
                NSItemProvider(object: Bundle.main.bundleURL as NSURL)
            }
    }
}
