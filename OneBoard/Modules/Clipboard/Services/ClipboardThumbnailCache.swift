import AppKit
import ImageIO

/// 只在后台解码列表所需的小图，滚动/悬停不再反复解码原始截图。
@MainActor
enum ClipboardThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func image(for entry: ClipboardEntry) async -> NSImage? {
        guard entry.isImage else { return nil }
        let key = entry.id.map { "\($0):\(entry.createdAt.timeIntervalSince1970)" as NSString }
        if let key, let image = cache.object(forKey: key) { return image }
        let data = entry.data
        let cgImage = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 56,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
        guard !Task.isCancelled, let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        if let key { cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height) }
        return image
    }
}
