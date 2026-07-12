import AppKit
import SwiftUI

/// 截图捕获服务 — 自定义全屏遮罩 + 框选区域
@MainActor
final class ScreenshotCaptureService: NSObject {

    private var overlayWindow: NSWindow?

    /// 捕获屏幕截图（静默全屏截图 → 自定义遮罩框选）
    func captureRegion() async -> ScreenshotResult? {
        // 1. 静默截取全屏（后台线程）
        guard let fullScreenImage = await captureFullScreenCG() else {
            print("[Screenshot] 全屏截图失败")
            return nil
        }

        // 2. 显示自定义遮罩，等待用户框选
        let result: ScreenshotResult? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                guard let screen = NSScreen.main else { continuation.resume(returning: nil); return }
                var didResume = false
                let finish: (ScreenshotResult?) -> Void = { [weak self] result in
                    guard !didResume else { return }
                    didResume = true
                    DispatchQueue.main.async {
                        self?.overlayWindow?.close()
                        self?.overlayWindow = nil
                    }
                    continuation.resume(returning: result)
                }

                let eventManager = OverlayEventManager()
                let overlayView = ScreenshotOverlayContentView(
                    screenshot: fullScreenImage,
                    eventManager: eventManager
                )
                overlayView.onConfirm = { [weak eventManager] img, rect in
                    eventManager?.cleanup()
                    finish(ScreenshotResult(image: img, selectionRect: rect))
                }
                overlayView.onCancel = { [weak eventManager] in
                    eventManager?.cleanup()
                    finish(nil)
                }

                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                // close() 后仍由 overlayWindow 统一持有和释放，避免 AppKit 与 ARC 重复释放。
                window.isReleasedWhenClosed = false
                overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
                overlayView.autoresizingMask = [.width, .height]
                window.contentView = overlayView
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)

                self.overlayWindow = window
            }
        }
        return result
    }

    /// 在后台线程使用 screencapture 静默截取全屏
    private func captureFullScreenCG() async -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_fullscreen_\(UUID().uuidString).png"
        let exitCode = await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-x", "-t", "png", tmpPath]
            task.launch()
            task.waitUntilExit()
            return task.terminationStatus
        }.value
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }
        guard exitCode == 0,
              let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            print("[Screenshot] screencapture 失败, exitCode=\(exitCode)")
            return nil
        }
        print("[Screenshot] 全屏截图完成, pixelSize=\(AnnotationService.pixelSize(for: image))")
        return image
    }
}
