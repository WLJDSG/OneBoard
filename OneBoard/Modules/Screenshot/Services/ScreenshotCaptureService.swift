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
            PermissionManager.shared.promptScreenRecordingPermission()
            return nil
        }
        return await captureWithSystemSelection()
    }

    /// 使用 macOS 系统交互式截图入口，保证快捷键触发后进入原生框选蒙版。
    private func captureWithSystemSelection() async -> NSImage? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-c", "-x"]
            process.terminationHandler = { process in
                DispatchQueue.main.async {
                    guard process.terminationStatus == 0 else {
                        print("[Screenshot] 系统截图已取消或失败: \(process.terminationStatus)")
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: Self.imageFromPasteboard())
                }
            }

            do {
                try process.run()
            } catch {
                print("[Screenshot] 启动系统截图失败: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    private static func imageFromPasteboard() -> NSImage? {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return NSImage(data: data)
        }
        print("[Screenshot] 系统截图完成，但剪贴板中没有图片")
        return nil
    }

    /// 保留自定义遮罩实现，后续需要 Snipaste 风格增强时可继续迭代。
    private func captureWithCustomOverlay() async -> NSImage? {
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
