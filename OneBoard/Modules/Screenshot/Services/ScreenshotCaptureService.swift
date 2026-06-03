import AppKit
import SwiftUI

/// 截图捕获服务
final class ScreenshotCaptureService {
    private var overlayWindow: NSWindow?
    private var continuation: CheckedContinuation<NSImage?, Never>?

    /// 捕获屏幕截图（区域选择模式）
    func captureRegion() async -> NSImage? {
        // 检查屏幕录制权限
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            print("[Screenshot] 缺少屏幕录制权限")
            PermissionManager.shared.promptScreenRecordingPermission()
            return nil
        }

        // 截取全屏
        guard let screenshot = captureFullScreen() else {
            print("[Screenshot] 全屏截图失败")
            return nil
        }

        // 显示区域选择遮罩窗口
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlay(screenshot: screenshot)
        }
    }

    // MARK: - 全屏截图

    private func captureFullScreen() -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let rect = screen.frame

        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    // MARK: - 区域选择遮罩

    private func showOverlay(screenshot: NSImage) {
        let screenFrame = NSScreen.main?.frame ?? .zero

        let overlayVC = NSHostingController(
            rootView: ScreenshotOverlayView(
                screenshot: screenshot,
                onConfirm: { [weak self] image in
                    self?.dismissOverlay(with: image)
                },
                onCancel: { [weak self] in
                    self?.dismissOverlay(with: nil)
                }
            )
        )

        let window = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentViewController = overlayVC
        window.makeKeyAndOrderFront(nil)

        self.overlayWindow = window
    }

    private func dismissOverlay(with image: NSImage?) {
        overlayWindow?.close()
        overlayWindow = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}