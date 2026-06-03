import SwiftUI

/// 置顶贴图视图
struct PinnedScreenshotView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Image(nsImage: image)
            .resizable()
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
