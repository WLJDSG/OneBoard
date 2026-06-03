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
            print("[Screenshot] 无屏幕录制权限，弹出权限引导")
            PermissionManager.shared.promptScreenRecordingPermission()
            return nil
        }
        print("[Screenshot] 权限检查通过，开始全屏截图...")
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

    /// 主方案：screencapture 命令行 + stderr 诊断
    private func captureFullScreenViaSC() -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_screenshot_\(UUID().uuidString).png"
        let displayID = CGMainDisplayID()
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        // 不指定 -D，让 screencapture 自动选择主显示器，避免 displayID 兼容问题
        task.arguments = ["-t", "png", "-x", tmpPath]
        // 捕获 stderr 用于诊断
        let errorPipe = Pipe()
        task.standardError = errorPipe
        task.launch()
        task.waitUntilExit()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 {
            let stderr = String(data: errorData, encoding: .utf8) ?? ""
            print("[Screenshot] screencapture 失败, exit=\(task.terminationStatus), displayID=\(displayID), stderr=\(stderr)")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        guard let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            print("[Screenshot] 无法读取 screencapture 输出: \(tmpPath)")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        print("[Screenshot] screencapture 成功, displayID=\(displayID), size=\(image.size)")
        return image
    }

    /// 备选：CGWindowListCreateImage
    private func captureFullScreenViaCGWindowList() -> NSImage? {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            print("[Screenshot] 无法获取任何 NSScreen")
            return nil
        }
        let screenRect = screen.frame
        guard let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            print("[Screenshot] CGWindowListCreateImage 返回 nil, screen=\(screenRect)")
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: screenRect.size)
        print("[Screenshot] CGWindowListCreateImage 成功, size=\(image.size)")
        return image
    }

    /// 尝试全屏截图：screencapture → CGWindowList → 最终失败
    private func captureFullScreenWithFallback() -> NSImage? {
        print("[Screenshot] 开始全屏截图...")
        if let image = captureFullScreenViaSC() {
            return image
        }
        print("[Screenshot] screencapture 失败，回退到 CGWindowListCreateImage")
        if let image = captureFullScreenViaCGWindowList() {
            return image
        }
        print("[Screenshot] 所有截图方案均失败")
        return nil
    }

    // MARK: - 区域选择遮罩

    private func showOverlay(screenshot: NSImage) {
        // 优先鼠标所在屏幕，兼容菜单栏 app 无 key window 场景
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            print("[Screenshot] 无法获取屏幕，无法显示遮罩")
            dismissOverlay(with: nil)
            return
        }
        let screenFrame = screen.frame
        print("[Screenshot] 显示遮罩窗口, screen=\(screenFrame)")

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
