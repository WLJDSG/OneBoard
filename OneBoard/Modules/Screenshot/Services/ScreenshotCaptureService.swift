import AppKit
import SwiftUI

/// 截图捕获服务
@MainActor
final class ScreenshotCaptureService: NSObject {
    private var overlayWindow: NSWindow?
    private var continuation: CheckedContinuation<NSImage?, Never>?

    /// 捕获屏幕截图（区域选择模式）
    func captureRegion() async -> NSImage? {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            print("[Screenshot] 缺少屏幕录制权限")
            await MainActor.run {
                PermissionManager.shared.promptScreenRecordingPermission()
            }
            return nil
        }

        guard let screenshot = captureFullScreen() else {
            print("[Screenshot] 全屏截图失败")
            await MainActor.run {
                PermissionManager.shared.promptScreenRecordingPermission()
            }
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showOverlay(screenshot: screenshot)
        }
    }

    // MARK: - 全屏截图（绕过 SDK 限制，运行时动态调用）

    private func captureFullScreen() -> NSImage? {
        // CGDisplayCreateImage 在 SDK 26.5 被标记 unavailable，但运行时仍可用
        // 使用 dlsym 动态查找函数地址绕过编译期限制
        typealias CGDisplayCreateImageFunc = @convention(c) (CGDirectDisplayID) -> CGImage?
        let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGDisplayCreateImage")
        guard let sym = sym, let fn = unsafeBitCast(sym, to: CGDisplayCreateImageFunc?.self) else {
            return nil
        }
        guard let cgImage = fn(CGMainDisplayID()) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - 区域选择遮罩

    private func showOverlay(screenshot: NSImage) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // 使用简化的 SwiftUI 遮罩
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
        overlayVC.view.wantsLayer = true
        overlayVC.view.layer?.backgroundColor = NSColor.clear.cgColor

        // 使用 NSWindow（不是 NSPanel），borderless 风格更稳定
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.contentViewController = overlayVC
        window.acceptsMouseMovedEvents = true
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayVC.view)

        self.overlayWindow = window
    }

    private func dismissOverlay(with image: NSImage?) {
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}
