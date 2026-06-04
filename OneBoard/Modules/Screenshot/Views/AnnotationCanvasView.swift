import SwiftUI

/// 标注画布视图（仅含截图和标注层，工具栏已分离为独立悬浮窗）
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
    @State private var textFieldValue: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            imageCanvas

            // 文字标注输入浮层（新增文字）
            if viewModel.isTextInput {
                textInputOverlay
            }

            // 文字标注编辑浮层（编辑已有文字）
            if viewModel.editingTextLayerID != nil {
                textEditOverlay
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Esc
                    if viewModel.isTextInput {
                        viewModel.cancelTextInput()
                    } else if viewModel.editingTextLayerID != nil {
                        viewModel.cancelEditText()
                    } else {
                        onClose()
                    }
                    return nil
                }
                // Delete 键删除选中的文字标注
                if event.keyCode == 51, viewModel.selectedTextLayerID != nil {
                    viewModel.deleteSelectedTextLayer()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }

    // MARK: - 图片画布

    private var imageCanvas: some View {
        GeometryReader { geometry in
            let fitted = fittedImageFrame(in: geometry.size)

            ZStack {
                Color.clear

                ZStack {
                    Image(nsImage: baseImage)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)

                    // 标注图层
                    ForEach(annotationService.layers) { layer in
                        AnnotationLayerView(
                            layer: layer,
                            isSelected: viewModel.selectedTextLayerID == layer.id,
                            onDoubleTap: {
                                if layer.tool == .text {
                                    viewModel.selectedTextLayerID = layer.id
                                    viewModel.enterTextEdit()
                                }
                            }
                        )
                    }

                    // 当前正在绘制的图层
                    if let drawingLayer = annotationService.currentDrawingLayer {
                        AnnotationLayerView(
                            layer: drawingLayer,
                            isSelected: false,
                            onDoubleTap: {}
                        )
                        .opacity(0.7)
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
            }
        }
    }

    // MARK: - 文字输入浮层

    private var textInputOverlay: some View {
        VStack(spacing: 6) {
            TextField("输入文字…", text: $textFieldValue)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundColor(Color(nsColor: annotationService.selectedColor))
                .frame(minWidth: 120, minHeight: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .focused($isTextFieldFocused)
                .onSubmit {
                    viewModel.commitText(textFieldValue)
                    textFieldValue = ""
                }
                .onAppear {
                    textFieldValue = ""
                    isTextFieldFocused = true
                }
                // 焦点丢失时自动提交文字（光标在截图外激活 → 文字保留在图片上）
                .onChange(of: isTextFieldFocused) { focused in
                    if !focused, !textFieldValue.isEmpty {
                        viewModel.commitText(textFieldValue)
                        textFieldValue = ""
                    }
                }

            HStack(spacing: 8) {
                Button("取消") {
                    viewModel.cancelTextInput()
                    textFieldValue = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))

                Button("确定") {
                    viewModel.commitText(textFieldValue)
                    textFieldValue = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
        .position(x: viewModel.textInputPoint.x, y: viewModel.textInputPoint.y - 40)
    }

    // MARK: - 文字编辑浮层

    private var textEditOverlay: some View {
        Group {
            if let layerID = viewModel.editingTextLayerID,
               let layer = annotationService.layers.first(where: { $0.id == layerID }) {
                VStack(spacing: 6) {
                    TextField("编辑文字…", text: Binding(
                        get: { layer.text ?? "" },
                        set: { newValue in
                            if let idx = annotationService.layers.firstIndex(where: { $0.id == layerID }) {
                                annotationService.layers[idx].text = newValue
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: layer.fontSize))
                    .foregroundColor(Color(nsColor: layer.color))
                    .frame(minWidth: 120, minHeight: 28)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        viewModel.commitEditText(layer.text ?? "")
                    }
                    .onAppear {
                        isTextFieldFocused = true
                    }

                    HStack(spacing: 8) {
                        Button("取消") { viewModel.cancelEditText() }
                            .buttonStyle(.plain).font(.system(size: 11))
                        Button("确定") { viewModel.commitEditText(layer.text ?? "") }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                .position(x: layer.rect.midX, y: layer.rect.minY - 40)
            }
        }
    }

    // MARK: - 布局

    private func fittedImageFrame(in container: CGSize) -> CGRect {
        let imageSize = baseImage.size
        let scale = min(container.width / imageSize.width, container.height / imageSize.height, 1)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }
}

/// 单个标注图层视图
struct AnnotationLayerView: View {
    let layer: AnnotationLayer
    let isSelected: Bool
    let onDoubleTap: () -> Void

    var body: some View {
        ZStack {
            layerContent
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
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
                .allowsHitTesting(false)
        case .ellipse:
            Ellipse()
                .stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth)
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
                .allowsHitTesting(false)
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
            .allowsHitTesting(false)
        case .text:
            textLayerView
        case .mosaic:
            MosaicPreview()
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
                .allowsHitTesting(false)
        }
    }

    private var textLayerView: some View {
        ZStack(alignment: .topTrailing) {
            Text(layer.text ?? "")
                .font(.system(size: layer.fontSize))
                .foregroundColor(Color(nsColor: layer.color))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(minWidth: 40, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .position(x: layer.rect.midX, y: layer.rect.midY)
        }
        .frame(width: layer.rect.width, height: layer.rect.height)
        .position(x: layer.rect.midX, y: layer.rect.midY)
        .contentShape(Rectangle())
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
