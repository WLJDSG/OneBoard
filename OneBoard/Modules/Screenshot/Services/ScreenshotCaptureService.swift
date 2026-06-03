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
        guard let screenshot = captureFullScreenWithFallback() else {
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

    // MARK: - 全屏截图（使用 CGWindowListCreateImage 公开 API）

    private func captureFullScreen() -> NSImage? {
        // CGWindowListCreateImage 是公开 API，可捕获全屏窗口内容
        // .bestResolution 返回 Retina 分辨率（像素尺寸），NSImage.size 使用屏幕点尺寸保证坐标计算正确
        guard let screen = NSScreen.main,
              let cgImage = CGWindowListCreateImage(
                .infinite,
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
              ) else {
            print("[Screenshot] CGWindowListCreateImage 返回 nil")
            return nil
        }
        // size 使用屏幕点坐标尺寸（而非像素尺寸），确保后续裁剪坐标计算正确
        return NSImage(cgImage: cgImage, size: screen.frame.size)
    }

    /// 备选方案：使用 screencapture 命令行（CGWindowListCreateImage 失败时回退）
    private func captureFullScreenViaSC() -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_screenshot_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-t", "png", "-x", "-D", "1", tmpPath]
        task.launch()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        return image
    }

    /// 尝试全屏截图，优先 CGWindowListCreateImage，失败则回退到 screencapture
    private func captureFullScreenWithFallback() -> NSImage? {
        if let image = captureFullScreen() {
            return image
        }
        print("[Screenshot] CGWindowListCreateImage 失败，回退到 screencapture")
        return captureFullScreenViaSC()
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
