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

    /// 请求辅助功能权限（仅打开设置页，不弹 App 内对话框）
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
        // 屏幕录制权限在截图触发时再检查
        return missing
    }

    /// 打开辅助功能权限页并显示拖拽引导
    @MainActor
    func promptAccessibilityPermission() {
        openAccessibilitySettings()
        PermissionGuideWindowManager.shared.show(for: .accessibility)
    }

    /// 打开系统设置中对应权限页面
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// 打开屏幕录制权限页并显示拖拽引导
    @MainActor
    func promptScreenRecordingPermission() {
        openScreenRecordingSettings()
        PermissionGuideWindowManager.shared.show(for: .screenRecording)
    }
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

    var hasActiveFlow: Bool {
        currentKind != nil
    }

    private init() {}

    func show(for kind: OneBoardPermissionKind, revokeMode: Bool = false) {
        NSWorkspace.shared.open(kind.settingsURL)

        self.currentKind = kind
        self.revokeMode = revokeMode

        // revoke 模式不显示悬浮引导窗口，只打开系统设置并轮询
        if revokeMode {
            panel?.close()
            panel = nil
            startPermissionPolling()
            return
        }

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
        startPermissionPolling()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        currentKind = nil
        revokeMode = false
    }

    private func startPermissionPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let currentKind = self.currentKind else { return }
                let completed: Bool
                switch currentKind {
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
                    self.finishFlow()
                }
            }
        }
    }

    private func finishFlow() {
        closeSystemSettings()
        hide()
        SettingsWindowManager.shared.show()
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
