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

    @State private var textInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
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

            Divider()

            // 标注画布
            ZStack {
                // 截图背景
                Image(nsImage: baseImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // 已完成的标注图层
                ForEach(annotationService.layers) { layer in
                    AnnotationLayerView(layer: layer)
                }

                // 当前正在绘制的图层
                if let drawingLayer = annotationService.currentDrawingLayer {
                    AnnotationLayerView(layer: drawingLayer)
                        .opacity(0.6)
                }

                // 文字输入框
                if viewModel.isTextInput {
                    textInputOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let location = value.location
                        if !viewModel.isDrawing {
                            viewModel.startDrawing(at: location)
                        }
                        viewModel.updateDrawing(to: location)
                    }
                    .onEnded { _ in
                        viewModel.endDrawing()
                    }
            )
        }
    }

    // MARK: - 文字输入

    private var textInputOverlay: some View {
        VStack {
            Spacer()
            HStack {
                TextField("输入文字...", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        viewModel.commitText(textInput)
                        textInput = ""
                    }

                Button("确定") {
                    viewModel.commitText(textInput)
                    textInput = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.bottom, 20)
        }
    }
}

/// 单个标注图层视图
struct AnnotationLayerView: View {
    let layer: AnnotationLayer

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch layer.tool {
                case .rectangle:
                    Rectangle()
                        .stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth)
                        .frame(width: layer.rect.width, height: layer.rect.height)
                        .position(x: layer.rect.midX, y: layer.rect.midY)

                case .line:
                    Path { path in
                        path.move(to: CGPoint(x: layer.rect.minX, y: layer.rect.minY))
                        path.addLine(to: CGPoint(x: layer.rect.maxX, y: layer.rect.maxY))
                    }
                    .stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth)

                case .highlight:
                    Rectangle()
                        .fill(Color(nsColor: layer.color).opacity(0.3))
                        .frame(width: layer.rect.width, height: layer.rect.height)
                        .position(x: layer.rect.midX, y: layer.rect.midY)

                case .text:
                    if let text = layer.text {
                        Text(text)
                            .font(.system(size: 18))
                            .foregroundColor(Color(nsColor: layer.color))
                            .padding(4)
                            .background(Color.white.opacity(0.6))
                            .cornerRadius(3)
                            .position(x: layer.rect.midX, y: layer.rect.midY)
                    }
                }
            }
        }
    }
}