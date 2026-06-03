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

    // MARK: - 全屏截图

    /// 主方案：使用 screencapture 命令行（最可靠，正确处理权限和所有显示器）
    private func captureFullScreenViaSC() -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_screenshot_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        // -t png: PNG 格式
        // -x: 静默模式（无提示音）
        // -D <displayID>: 指定显示器（使用系统主显示器 ID，而非硬编码 1）
        let displayID = CGMainDisplayID()
        task.arguments = ["-t", "png", "-x", "-D", "\(displayID)", tmpPath]
        task.launch()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        print("[Screenshot] screencapture 成功, displayID=\(displayID), size=\(image.size)")
        return image
    }

    /// 备选方案：CGWindowListCreateImage（公开 API，快速但可能因权限返回纯黑图）
    private func captureFullScreenViaCGWindowList() -> NSImage? {
        guard let screen = NSScreen.main else {
            print("[Screenshot] NSScreen.main 为 nil")
            return nil
        }
        // 使用屏幕 frame（非 CGRect.infinite），确保捕获正确的显示区域
        let screenRect = screen.frame
        guard let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            print("[Screenshot] CGWindowListCreateImage 返回 nil")
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: screenRect.size)
        print("[Screenshot] CGWindowListCreateImage 成功, size=\(image.size)")
        return image
    }

    /// 尝试全屏截图：优先 screencapture（最可靠），失败则回退 CGWindowList
    private func captureFullScreenWithFallback() -> NSImage? {
        // screencapture 最可靠，优先使用
        if let image = captureFullScreenViaSC() {
            return image
        }
        print("[Screenshot] screencapture 失败，回退到 CGWindowListCreateImage")
        return captureFullScreenViaCGWindowList()
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
