import AppKit

extension NSImage {
    /// 将 NSImage 转换为 PNG 数据
    var pngData: Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// 将 NSImage 转换为 JPEG 数据
    func jpegData(compressionFactor: Float = 0.85) -> Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }

    /// 缩放图片到指定尺寸
    func resized(to targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    /// 等比缩放，适配最大尺寸
    func resized(maxSize: NSSize) -> NSImage {
        let ratio = min(maxSize.width / self.size.width, maxSize.height / self.size.height, 1.0)
        let newSize = NSSize(width: self.size.width * ratio, height: self.size.height * ratio)
        return resized(to: newSize)
    }

    /// 从 Data 创建 NSImage（使用系统自带初始化器）
}