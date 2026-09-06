import AppKit
import SwiftUI

struct ScreenshotDisplayCapturePlan: Equatable {
    let displayNumber: Int
    let screenFrame: CGRect

    static func make(screenFrames: [CGRect]) -> [ScreenshotDisplayCapturePlan] {
        screenFrames.enumerated().map { index, frame in
            ScreenshotDisplayCapturePlan(displayNumber: index + 1, screenFrame: frame)
        }
    }
}

private final class ScreenshotOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// 截图捕获服务 — 自定义全屏遮罩 + 框选区域
@MainActor
final class ScreenshotCaptureService: NSObject {

    private var overlayWindows: [NSWindow] = []
    private var overlayEventManagers: [OverlayEventManager] = []

    /// 捕获屏幕截图（静默全屏截图 → 自定义遮罩框选）
    func captureRegion() async -> ScreenshotResult? {
        // 每块显示器独立截图，避免混合 Retina/非 Retina 像素后按主屏尺寸误裁。
        let windowFrames = ScreenshotWindowCandidate.snapshot()
        let screens = NSScreen.screens
        let plans = ScreenshotDisplayCapturePlan.make(screenFrames: screens.map(\.frame))
        var captures: [(screen: NSScreen, plan: ScreenshotDisplayCapturePlan, image: NSImage)] = []
        for (screen, plan) in zip(screens, plans) {
            if let image = await captureDisplay(displayNumber: plan.displayNumber) {
                captures.append((screen, plan, image))
            }
        }
        guard !captures.isEmpty else {
            print("[Screenshot] 所有显示器截图均失败")
            return nil
        }

        // 每块显示器各放一个遮罩窗口；在哪块屏幕框选，就裁哪块屏幕的截图。
        let result: ScreenshotResult? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                var didResume = false
                let finish: (ScreenshotResult?) -> Void = { [weak self] result in
                    guard !didResume else { return }
                    didResume = true
                    DispatchQueue.main.async {
                        self?.closeOverlay()
                        continuation.resume(returning: result)
                    }
                }

                for capture in captures {
                    let eventManager = OverlayEventManager()
                    let overlayView = ScreenshotOverlayContentView(
                        screenshot: capture.image,
                        eventManager: eventManager,
                        windowCandidates: ScreenshotWindowCandidate.localRects(windowFrames, screenFrame: capture.plan.screenFrame)
                    )
                    overlayView.onConfirm = { img, rect, action in
                        finish(ScreenshotResult(image: img, selectionRect: rect, action: action))
                    }
                    overlayView.onCancel = { finish(nil) }

                    let window = ScreenshotOverlayWindow(
                        contentRect: capture.plan.screenFrame,
                        styleMask: .borderless,
                        backing: .buffered,
                        defer: false
                    )
                    window.level = .screenSaver
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    window.isOpaque = true
                    window.backgroundColor = .black
                    window.hasShadow = false
                    window.acceptsMouseMovedEvents = true
                    window.isReleasedWhenClosed = false
                    overlayView.frame = NSRect(origin: .zero, size: capture.plan.screenFrame.size)
                    overlayView.autoresizingMask = [.width, .height]
                    window.contentView = overlayView
                    window.orderFrontRegardless()

                    self.overlayWindows.append(window)
                    self.overlayEventManagers.append(eventManager)
                }

                let mouseLocation = NSEvent.mouseLocation
                let activeWindow = self.overlayWindows.first { $0.frame.contains(mouseLocation) }
                    ?? self.overlayWindows.first
                activeWindow?.makeKey()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return result
    }

    /// 标注阶段仍复用原框选遮罩；完成或取消整个截图会话时统一关闭。
    func closeOverlay() {
        overlayEventManagers.forEach { $0.cleanup() }
        overlayEventManagers.removeAll()
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()
    }

    /// `screencapture -D` 的编号与 `NSScreen.screens` 顺序一致：主屏为 1，其余屏幕依次递增。
    private func captureDisplay(displayNumber: Int) async -> NSImage? {
        let tmpPath = NSTemporaryDirectory() + "oneboard_display_\(displayNumber)_\(UUID().uuidString).png"
        let exitCode = await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-D", "\(displayNumber)", "-t", "png", tmpPath]
            do {
                try task.run()
            } catch {
                return Int32(-1)
            }
            task.waitUntilExit()
            return task.terminationStatus
        }.value
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }
        guard exitCode == 0,
              let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            print("[Screenshot] 显示器 \(displayNumber) 截图失败, exitCode=\(exitCode)")
            return nil
        }
        print("[Screenshot] 显示器 \(displayNumber) 截图完成, pixelSize=\(AnnotationService.pixelSize(for: image))")
        return image
    }
}
