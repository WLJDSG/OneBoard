import SwiftUI

/// 全屏遮罩 - 区域选择
struct ScreenshotOverlayView: View {
    let screenshot: NSImage
    let onConfirm: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var selectionRect: CGRect = .zero
    @State private var isDragging: Bool = false
    @State private var dragStart: CGPoint = .zero

    var body: some View {
        ZStack {
            // 半透明背景 + 截图
            Image(nsImage: screenshot)
                .resizable()
                .ignoresSafeArea()
                .opacity(0.5)

            // 选择区域高亮
            if isDragging || selectionRect != .zero {
                Rectangle()
                    .fill(Color.clear)
                    .frame(
                        width: abs(selectionRect.width),
                        height: abs(selectionRect.height)
                    )
                    .overlay(
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 1.5)
                    )
                    .position(
                        x: selectionRect.midX,
                        y: selectionRect.midY
                    )
            }

            // 提示文字
            if !isDragging && selectionRect == .zero {
                VStack(spacing: 12) {
                    Text("拖拽选择截图区域")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Text("按 Enter 确认 · Esc 取消")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.6))
                )
            }

            // 确认/取消按钮
            if selectionRect != .zero {
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        Button("取消 (Esc)") {
                            onCancel()
                        }
                        .keyboardShortcut(.escape, modifiers: [])

                        Button("确认 (Enter)") {
                            confirmSelection()
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .primaryButtonStyle()
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStart = value.startLocation
                    }
                    let current = value.location
                    selectionRect = CGRect(
                        x: min(dragStart.x, current.x),
                        y: min(dragStart.y, current.y),
                        width: abs(current.x - dragStart.x),
                        height: abs(current.y - dragStart.y)
                    )
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
    }

    private func confirmSelection() {
        guard selectionRect.width > 10, selectionRect.height > 10 else { return }

        // 裁剪图片
        let scale = screenshot.size.width / NSScreen.main!.frame.width
        let cropRect = CGRect(
            x: selectionRect.origin.x * scale,
            y: (NSScreen.main!.frame.height - selectionRect.maxY) * scale,
            width: selectionRect.width * scale,
            height: selectionRect.height * scale
        )

        if let cropped = cropImage(screenshot, to: cropRect) {
            onConfirm(cropped)
        }
    }

    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: rect) else {
            return nil
        }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}