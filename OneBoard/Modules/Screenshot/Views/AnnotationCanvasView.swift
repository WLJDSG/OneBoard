import SwiftUI

/// 标注画布视图（含截图、标注层、工具栏）
struct AnnotationCanvasView: View {
    let baseImage: NSImage
    @ObservedObject var annotationService: AnnotationService
    @ObservedObject var viewModel: AnnotationViewModel

    let onCopy: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onPin: (NSImage) -> Void
    let onOCR: (NSImage) -> Void
    let onTranslate: (NSImage) -> Void
    let onClose: () -> Void

    @State private var keyMonitor: Any?
    @State private var globalKeyMonitor: Any?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .ignoresSafeArea()

            imageCanvas

            AnnotationToolbarView(
                    annotationService: annotationService,
                    viewModel: viewModel,
                    onCopy: onCopy,
                    onSave: onSave,
                    onPin: onPin,
                    onOCR: onOCR,
                    onTranslate: onTranslate,
                    onClose: onClose,
                    baseImage: baseImage
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    onClose()
                    return nil
                }
                return event
            }
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    Task { @MainActor in
                        onClose()
                    }
                }
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let globalKeyMonitor {
                NSEvent.removeMonitor(globalKeyMonitor)
                self.globalKeyMonitor = nil
            }
        }
    }

    private var imageCanvas: some View {
        GeometryReader { geometry in
            let fitted = fittedImageFrame(in: geometry.size)

            ZStack {
                Color.clear

                ZStack {
                    Image(nsImage: baseImage)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)

                    ForEach(annotationService.layers) { layer in
                        AnnotationLayerView(layer: layer)
                    }

                    if let drawingLayer = annotationService.currentDrawingLayer {
                        AnnotationLayerView(layer: drawingLayer)
                            .opacity(0.7)
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let location = pointInImage(value.location, imageFrame: fitted)
                            if !viewModel.isDrawing {
                                viewModel.startDrawing(at: location)
                            }
                            viewModel.updateDrawing(to: location)
                        }
                        .onEnded { value in
                            viewModel.updateDrawing(to: pointInImage(value.location, imageFrame: fitted))
                            viewModel.endDrawing()
                        }
                )
            }
        }
    }

    private func fittedImageFrame(in container: CGSize) -> CGRect {
        let toolbarReserve: CGFloat = 44
        let available = CGSize(width: container.width, height: max(container.height - toolbarReserve, 1))
        let imageSize = baseImage.size
        let scale = min(available.width / imageSize.width, available.height / imageSize.height, 1)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: max(container.height - toolbarReserve - height, 0),
            width: width,
            height: height
        )
    }

    private func pointInImage(_ point: CGPoint, imageFrame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x - imageFrame.minX, 0), imageFrame.width),
            y: min(max(point.y - imageFrame.minY, 0), imageFrame.height)
        )
    }

}

/// 单个标注图层视图
struct AnnotationLayerView: View {
    let layer: AnnotationLayer

    var body: some View {
        layerContent
    }

    @ViewBuilder
    private var layerContent: some View {
        switch layer.tool {
        case .cursor:
            EmptyView()
        case .rectangle:
            Rectangle()
                .stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth)
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
        case .ellipse:
            Ellipse()
                .stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth)
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
        case .line, .arrow:
            Path { path in
                let start = layer.startPoint ?? CGPoint(x: layer.rect.minX, y: layer.rect.minY)
                let end = layer.endPoint ?? CGPoint(x: layer.rect.maxX, y: layer.rect.maxY)
                path.move(to: start)
                path.addLine(to: end)
                if layer.tool == .arrow {
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let length: CGFloat = 12
                    let spread: CGFloat = .pi / 7
                    path.move(to: end)
                    path.addLine(to: CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)))
                    path.move(to: end)
                    path.addLine(to: CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread)))
                }
            }
            .stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth)
        case .highlight:
            Rectangle()
                .fill(Color(nsColor: layer.color).opacity(0.3))
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
        case .mosaic:
            MosaicPreview()
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
        }
    }
}
private struct MosaicPreview: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.68)))
            for x in stride(from: CGFloat.zero, to: size.width, by: cell) {
                for y in stride(from: CGFloat.zero, to: size.height, by: cell) {
                    let seed = sin((x + 17) * 12.9898 + (y + 23) * 78.233) * 43758.5453
                    let random = seed - floor(seed)
                    let alpha = 0.38 + random * 0.48
                    let inset = random > 0.55 ? CGFloat(0) : CGFloat(1)
                    context.fill(
                        Path(CGRect(x: x + inset, y: y + inset, width: cell + 1 - inset, height: cell + 1 - inset)),
                        with: .color(.white.opacity(alpha))
                    )
                }
            }
        }
    }
}
