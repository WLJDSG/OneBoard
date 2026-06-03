import AppKit

/// 权限管理器
final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}

    // MARK: - 辅助功能权限

    /// 检查辅助功能权限
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能权限（弹出系统对话框）
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
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

    /// 弹出权限引导对话框
    func promptAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        OneBoard 需要「辅助功能」权限来实现自动粘贴功能。

        请在系统设置中开启：
        系统设置 → 隐私与安全性 → 辅助功能 → 开启 OneBoard
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.icon = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
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

    /// 弹出屏幕录制权限引导对话框
    func promptScreenRecordingPermission() {
        if !hasScreenRecordingPermission {
            CGRequestScreenCaptureAccess()
        }

        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = """
        OneBoard 需要「屏幕录制」权限来实现截图功能。

        请在系统设置中开启：
        系统设置 → 隐私与安全性 → 屏幕录制 → 开启 OneBoard
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.icon = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
