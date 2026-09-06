import AppKit

/// 在遮罩出现前获取窗口顺序；仅保存几何信息，不读取窗口内容。
enum ScreenshotWindowCandidate {
    static func snapshot() -> [CGRect] {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return [] }
        return windows.compactMap { info in
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= 0, layer <= NSWindow.Level.statusBar.rawValue,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary),
                  rect.width >= 24, rect.height >= 24 else { return nil }
            return appKitRect(from: rect, primaryScreenHeight: primary.frame.height)
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
