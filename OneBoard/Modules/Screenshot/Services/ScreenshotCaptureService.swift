import AppKit
import SwiftUI

/// 截图捕获服务
@MainActor
final class ScreenshotCaptureService: NSObject {
    private var overlayWindow: NSWindow?
    private var continuation: CheckedContinuation<ScreenshotResult?, Never>?

    /// 捕获屏幕截图（区域选择模式）
    /// 先冻结全屏 → 用户框选 → 返回截图和选区位置
    func captureRegion() async -> ScreenshotResult? {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            PermissionManager.shared.promptScreenRecordingPermission()
            return nil
        }
        return await captureWithCustomOverlay()
    }

    /// 自定义冻结屏幕 + 框选方案
    private func captureWithCustomOverlay() async -> ScreenshotResult? {
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

        let overlayVC = NSHostingController(
            rootView: ScreenshotOverlayView(
                screenshot: screenshot,
                onConfirm: { [weak self] image, rect in
                    self?.dismissOverlay(with: ScreenshotResult(image: image, selectionRect: rect))
                },
                onCancel: { [weak self] in
                    self?.dismissOverlay(with: nil)
                }
            )
        )
        overlayVC.view.wantsLayer = true
        overlayVC.view.layer?.backgroundColor = NSColor.clear.cgColor

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

    private func dismissOverlay(with result: ScreenshotResult?) {
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}
