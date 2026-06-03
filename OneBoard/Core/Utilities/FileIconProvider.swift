import AppKit
import Quartz

/// 文件图标/缩略图提供器
enum FileIconProvider {

    /// 获取文件的 QuickLook 缩略图
    /// - Parameter url: 文件 URL
    /// - Parameter size: 缩略图尺寸
    /// - Returns: 缩略图 NSImage
    static func thumbnail(for url: URL, size: NSSize = NSSize(width: 48, height: 48)) -> NSImage? {
        let options: [CFString: Any] = [
            kQLThumbnailOptionIconModeKey: false,
            kQLThumbnailOptionScaleFactorKey: 1.0,
        ]

        guard let ref = QLThumbnailImageCreate(
            kCFAllocatorDefault,
            url as CFURL,
            size,
            options as CFDictionary
        ) else {
            return workspaceIcon(for: url)
        }

        return NSImage(cgImage: ref.takeRetainedValue(), size: size)
    }

    /// 获取文件的 Finder 图标（降级方案）
    static func workspaceIcon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 格式化文件大小
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}