import SwiftUI

/// 置顶贴图视图
struct PinnedScreenshotView: View {
    let image: NSImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 图片
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

            // 关闭按钮
            VStack(spacing: 4) {
                Button(action: closeWindow) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .padding(6)

                // 缩放按钮
                Button(action: {
                    scale = min(scale + 0.25, 5.0)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)

                Button(action: {
                    scale = max(scale - 0.25, 0.3)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func closeWindow() {
        if let window = NSApp.keyWindow {
            window.close()
        }
    }
}