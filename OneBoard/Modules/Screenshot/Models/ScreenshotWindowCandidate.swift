import AppKit

/// 在遮罩出现前获取窗口顺序；仅保存几何信息，不读取窗口内容。
enum ScreenshotWindowCandidate {
    static func snapshot() -> [CGRect] {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return [] }
        // Dock 的全屏桌面交互层也会出现在 excludeDesktopElements 结果中，且高于普通应用。
        // 按 Bundle ID 解析当前 PID，避免本地化名称以及 Dock 重启导致的误判。
        let dockPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier))
        return frames(from: windows, primaryScreenHeight: primary.frame.height, excludedOwnerPIDs: dockPIDs)
    }

    static func frames(from windows: [[String: Any]], primaryScreenHeight: CGFloat, excludedOwnerPIDs: Set<pid_t> = []) -> [CGRect] {
        // WindowServer 返回前到后顺序；浮动卡片、菜单和提示窗可高于 statusBar 层级。
        return windows.compactMap { info in
            if let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
               excludedOwnerPIDs.contains(pid) { return nil }
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= 0, layer <= NSWindow.Level.popUpMenu.rawValue,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary),
                  rect.width >= 24, rect.height >= 24 else { return nil }
            return appKitRect(from: rect, primaryScreenHeight: primaryScreenHeight)
        }
    }

    static func appKitRect(from quartzRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: quartzRect.minX, y: primaryScreenHeight - quartzRect.maxY,
               width: quartzRect.width, height: quartzRect.height)
    }

    static func localRects(_ frames: [CGRect], screenFrame: CGRect) -> [CGRect] {
        frames.compactMap { frame in
            let visible = frame.intersection(screenFrame)
            guard !visible.isNull, visible.width >= 24, visible.height >= 24 else { return nil }
            return visible.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        }
    }
}
