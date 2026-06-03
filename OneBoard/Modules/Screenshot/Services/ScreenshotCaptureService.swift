import AppKit
import SwiftUI

/// 截图捕获服务 — 使用系统原生截图工具 screencapture -i
@MainActor
final class ScreenshotCaptureService: NSObject {

    /// 捕获屏幕截图（调用系统原生交互式截图工具）
    func captureRegion() async -> ScreenshotResult? {
        print("[Screenshot] 启动 screencapture -i ...")
        let tmpPath = NSTemporaryDirectory() + "oneboard_\(UUID().uuidString).png"

        // 在后台线程执行 Process，避免阻塞主线程 run loop
        let exitCode: Int32 = await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-i", "-x", "-t", "png", tmpPath]
            task.launch()
            task.waitUntilExit()
            return task.terminationStatus
        }.value

        if exitCode != 0 {
            print("[Screenshot] screencapture -i 退出码=\(exitCode)（0=成功, 1=用户取消）")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }

        guard let image = NSImage(contentsOf: URL(fileURLWithPath: tmpPath)) else {
            print("[Screenshot] 无法读取截图文件")
            try? FileManager.default.removeItem(atPath: tmpPath)
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        print("[Screenshot] 截图成功, size=\(image.size)")

        // 以图片尺寸居中定位标注窗口
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let rect = CGRect(
            x: screenFrame.midX - image.size.width / 2,
            y: screenFrame.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        return ScreenshotResult(image: image, selectionRect: rect)
    }
}
