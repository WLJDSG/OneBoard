import AppKit

/// 原图坐标固定方格；预览与导出共用，拖动边界不会重新拉伸整片像素块。
enum MosaicPixels {
    static func make(image: NSImage, displaySize: CGSize, rect: CGRect, blockSize: CGFloat) -> CGImage? {
        guard rect.width > 0, rect.height > 0, displaySize.width > 0, displaySize.height > 0,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let cell = max(4, blockSize)
        let aligned = CGRect(x: floor(rect.minX / cell) * cell, y: floor(rect.minY / cell) * cell,
                             width: (ceil(rect.maxX / cell) - floor(rect.minX / cell)) * cell,
                             height: (ceil(rect.maxY / cell) - floor(rect.minY / cell)) * cell)
        let sx = CGFloat(source.width) / displaySize.width, sy = CGFloat(source.height) / displaySize.height
        func context(width: Int, height: Int) -> CGContext? {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let sample = context(width: max(1, Int(round(aligned.width / cell))),
                                   height: max(1, Int(round(aligned.height / cell)))) else { return nil }
        sample.setFillColor(NSColor.white.cgColor)
        sample.fill(CGRect(x: 0, y: 0, width: sample.width, height: sample.height))
        sample.interpolationQuality = .high
        sample.draw(source, in: CGRect(x: -aligned.minX / cell, y: (aligned.maxY - displaySize.height) / cell,
                                       width: displaySize.width / cell, height: displaySize.height / cell))
        guard let blocks = sample.makeImage(),
              let output = context(width: max(1, Int(round(rect.width * sx))),
                                   height: max(1, Int(round(rect.height * sy)))) else { return nil }
        output.interpolationQuality = .none
        output.draw(blocks, in: CGRect(x: (aligned.minX - rect.minX) * sx, y: (rect.maxY - aligned.maxY) * sy,
                                      width: aligned.width * sx, height: aligned.height * sy))
        return output.makeImage()
    }
}
