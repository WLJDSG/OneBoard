import AppKit

/// 预览与导出共用同一原图像素块，避免随机噪点及半透明泄露。
enum MosaicPixels {
    static func make(image: NSImage, displaySize: CGSize, rect: CGRect, blockSize: CGFloat) -> CGImage? {
        guard rect.width > 0, rect.height > 0, displaySize.width > 0, displaySize.height > 0,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(source.width) / displaySize.width, sy = CGFloat(source.height) / displaySize.height
        let crop = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
        guard let cropped = source.cropping(to: crop) else { return nil }
        let cell = max(4, blockSize)
        let width = max(1, Int(ceil(rect.width / cell))), height = max(1, Int(ceil(rect.height / cell)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
