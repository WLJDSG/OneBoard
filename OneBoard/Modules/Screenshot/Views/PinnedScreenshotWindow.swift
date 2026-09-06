import SwiftUI

/// 置顶贴图视图
struct PinnedScreenshotView: View {
    let image: NSImage
    let onClose: () -> Void
    private let sourcePixels: CGImage?

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.image = image
        self.onClose = onClose
        // 保留原始位图，避免 SwiftUI 按逻辑尺寸重新选择低分辨率 representation。
        self.sourcePixels = image.representations.compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }?.cgImage
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private var screenshotImage: Image {
        if let sourcePixels {
            return Image(decorative: sourcePixels, scale: CGFloat(sourcePixels.width) / max(image.size.width, 1))
        }
        return Image(nsImage: image)
    }

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        screenshotImage
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 0.3), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
            .onTapGesture(count: 2) {
                onClose()
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
