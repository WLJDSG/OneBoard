import AppKit
import SwiftUI

/// 截图捕获服务
/// 策略：优先全屏截图 + 自定义蒙版框选（冻结动态内容）
///       全屏截图失败时回退到系统截图工具 screencapture -i
@MainActor
final class ScreenshotCaptureService: NSObject {
    private var overlayWindow: NSWindow?
    private var continuation: CheckedContinuation<ScreenshotResult?, Never>?

    /// 捕获屏幕截图（区域选择模式）
    func captureRegion() async -> ScreenshotResult? {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            print("[Screenshot] 无屏幕录制权限，弹出权限引导")
            PermissionManager.shared.promptScreenRecordingPermission()
            return nil
        }

        print("[Screenshot] 权限检查通过")

        // 优先：全屏截图 + 自定义蒙版
        if let result = await captureWithCustomOverlay() {
            return result
        }

        // 回退：系统截图工具 screencapture -i
        print("[Screenshot] 自定义蒙版方案失败，回退到系统截图工具")
        return await captureWithSystemTool()
    }

    // MARK: - 方案一：全屏截图 + 自定义蒙版

    private func captureWithCustomOverlay() async -> ScreenshotResult? {
        guard let screenshot = captureFullScreen() else {
            print("[Screenshot] 全屏截图失败")
            return nil
        }

        print("[Screenshot] 全屏截图成功, size=\(screenshot.size), 显示蒙版...")
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showOverlay(screenshot: screenshot)
        }
    }

    /// 全屏截图：使用 screencapture 命令行
    private func captureFullScreen() -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_freeze_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-t", "png", "-x", tmpPath]
        let errorPipe = Pipe()
        task.standardError = errorPipe
        task.launch()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("[Screenshot] screencapture 失败, exit=\(task.terminationStatus), stderr=\(stderr)")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }

        guard let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            print("[Screenshot] 无法读取截图文件: \(tmpPath)")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        return image
    }

    // MARK: - 方案二：系统截图工具（回退）

    private func captureWithSystemTool() async -> ScreenshotResult? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_sys_\(UUID().uuidString).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        // -i: 交互式框选（系统原生 UI，类似 Cmd+Shift+4）
        task.arguments = ["-i", "-t", "png", tmpPath]
        task.launch()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            // 退出码 1 通常表示用户按 Esc 取消
            print("[Screenshot] screencapture -i 取消或失败, exit=\(task.terminationStatus)")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }

        guard let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            print("[Screenshot] 无法读取系统截图文件")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        print("[Screenshot] 系统截图成功, size=\(image.size)")

        // 系统截图不返回选区坐标，以图像尺寸居中定位标注窗口
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let rect = CGRect(
            x: screenFrame.midX - image.size.width / 2,
            y: screenFrame.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        return ScreenshotResult(image: image, selectionRect: rect)
    }

    // MARK: - 自定义蒙版窗口

    private func showOverlay(screenshot: NSImage) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            print("[Screenshot] 无法获取屏幕")
            dismissOverlay(with: nil)
            return
        }

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
            contentRect: screen.frame,
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
