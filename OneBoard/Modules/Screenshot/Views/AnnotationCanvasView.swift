import SwiftUI

/// 标注画布视图（仅含截图和标注层，工具栏已分离为独立悬浮窗）
struct AnnotationCanvasView: View {
    let baseImage: NSImage
    let displaySize: CGSize
    @ObservedObject var annotationService: AnnotationService
    @ObservedObject var viewModel: AnnotationViewModel

    let onCopy: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onPin: (NSImage) -> Void
    let onOCR: (NSImage) -> Void
    let onTranslate: (NSImage) -> Void
    let onClose: () -> Void

    @State private var keyMonitor: Any?
    @State private var canvasWindow: NSWindow?
    @State private var pressedOptionKeyCodes: Set<UInt16> = []
    @State private var textFieldValue: String = ""
    @State private var textInputResizeStartRect: CGRect?
    @State private var textInputResizeHandle: CanvasResizeHandle?
    @State private var isResizingTextInput: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            imageCanvas

            // 像素尺寸显示
            VStack {
                HStack {
                    Text(AnnotationService.pixelSizeDescription(for: baseImage))
                        .oneBoardFont(.monoCaption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            .allowsHitTesting(false)


            // 文字标注输入浮层（新增文字）
            if viewModel.isTextInput {
                textInputOverlay
            }

            if let id = viewModel.editingNumberLayerID,
               let layer = annotationService.layers.first(where: { $0.id == id }) {
                NumberAnnotationEditor(value: layer.numberValue ?? 1,
                    maximum: annotationService.layers.filter { $0.tool == .number }.count,
                    onSave: { annotationService.updateNumber(id: id, value: $0); viewModel.editingNumberLayerID = nil },
                    onCancel: { viewModel.editingNumberLayerID = nil })
                    .position(x: min(max(layer.rect.midX, 105), max(105, displaySize.width - 105)),
                              y: min(max(layer.rect.maxY + 40, 40), max(40, displaySize.height - 40)))
            }

            // 文字标注编辑浮层（编辑已有文字）
            if viewModel.editingTextLayerID != nil {
                textEditOverlay
            }
        }
        .coordinateSpace(name: "annotationCanvas")
        .transaction { $0.animation = nil }
        .background(WindowAccessor { window in
            canvasWindow = window
        })
        .onAppear {
            viewModel.setTextInputCommitHandler {
                viewModel.commitText(textFieldValue)
                textFieldValue = ""
                isTextFieldFocused = false
            }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                handleKeyboardEvent(event)
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .onChange(of: annotationService.selectedTool) { _, tool in
            guard viewModel.isTextInput, tool != .text, tool != .callout else { return }
            viewModel.commitText(textFieldValue)
            textFieldValue = ""
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
                            mosaicImage: baseImage,
                            onDoubleTap: {
                                if layer.tool == .text || layer.tool == .callout {
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
                            mosaicImage: baseImage,
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

    // MARK: - 文字输入浮层 (微信风格)

    private var textInputOverlay: some View {
        let rect = viewModel.textInputRect
        let fontSize = annotationService.fontSize
        let color = Color(nsColor: annotationService.selectedColor)

        return ZStack {
            // 透明背景 TextField，直接显示在图片上
            TextField("输入文字…", text: $textFieldValue)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .focused($isTextFieldFocused)
                .onSubmit {
                    viewModel.commitText(textFieldValue)
                    textFieldValue = ""
                }
                .onAppear {
                    textFieldValue = ""
                    DispatchQueue.main.async {
                        isTextFieldFocused = true
                    }
                }
                .onChange(of: annotationService.fontSize) { _, newSize in
                    // 字体变化时调整输入框大小
                    if !isResizingTextInput {
                        let newWidth = max(newSize * 8, 120)
                        let newHeight = max(newSize * 1.8, 30)
                        viewModel.textInputRect.size = CGSize(width: newWidth, height: newHeight)
                    }
                }
                .onChange(of: isTextFieldFocused) { _, focused in
                    if !focused, !isResizingTextInput {
                        viewModel.commitText(textFieldValue)
                        textFieldValue = ""
                    }
                }

            // 打字时显示虚线边框
            if isTextFieldFocused {
                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                    .allowsHitTesting(false)
            }

            // 固定画布坐标系内拖动边框手柄，不覆盖 TextField 的光标和选字操作。
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10)).foregroundStyle(color)
                .frame(width: 30, height: 16)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Rectangle())
                .position(x: rect.width / 2, y: -8)
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("annotationCanvas"))
                        .onChanged { value in
                            isResizingTextInput = true
                            if textInputResizeStartRect == nil {
                                textInputResizeStartRect = viewModel.textInputRect
                            }
                            let startRect = textInputResizeStartRect ?? rect
                            viewModel.textInputRect.origin = CGPoint(
                                x: startRect.origin.x + value.translation.width,
                                y: startRect.origin.y + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            textInputResizeStartRect = nil
                            isResizingTextInput = false
                            DispatchQueue.main.async {
                                isTextFieldFocused = true
                            }
                        }
                )

            // 缩放手柄
            ForEach(CanvasResizeHandle.allCases, id: \.self) { handle in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .position(handle.position(in: CGRect(origin: .zero, size: rect.size)))
                    .contentShape(Rectangle().size(width: 20, height: 20))
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("annotationCanvas"))
                            .onChanged { value in
                                isResizingTextInput = true
                                if textInputResizeStartRect == nil {
                                    textInputResizeStartRect = viewModel.textInputRect
                                    textInputResizeHandle = handle
                                }
                                let startRect = textInputResizeStartRect ?? rect
                                let activeHandle = textInputResizeHandle ?? handle
                                viewModel.textInputRect = activeHandle.resizedRect(
                                    from: startRect,
                                    translation: value.translation,
                                    minSize: CGSize(width: 40, height: 24)
                                )
                            }
                            .onEnded { _ in
                                textInputResizeStartRect = nil
                                textInputResizeHandle = nil
                                isResizingTextInput = false
                                DispatchQueue.main.async {
                                    isTextFieldFocused = true
                                }
                            }
                    )
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onChange(of: viewModel.textInputRect) { _, _ in viewModel.updateCalloutPreview() }
    }

    // MARK: - 文字编辑浮层 (微信风格)

    private var textEditOverlay: some View {
        Group {
            if let layerID = viewModel.editingTextLayerID,
               let layer = annotationService.layers.first(where: { $0.id == layerID }) {
                VStack(spacing: 8) {
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001))
                    )
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        viewModel.commitEditText(layer.text ?? "")
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isTextFieldFocused = true
                        }
                    }
                    .onChange(of: annotationService.fontSize) { _, _ in
                        // 字体大小变化时同步
                    }

                    HStack(spacing: 12) {
                        Button("取消") { viewModel.cancelEditText() }
                            .buttonStyle(.plain)
                            .oneBoardFont(.callout)
                            .foregroundColor(OneBoardColors.textSecondary)
                        Button("确定") {
                            viewModel.commitEditText(layer.text ?? "")
                        }
                        .buttonStyle(.plain)
                        .oneBoardFont(.callout)
                        .foregroundColor(OneBoardColors.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                        .fill(.ultraThinMaterial)
                        .shadow(color: OneBoardShadow.sm.color, radius: OneBoardShadow.sm.radius, y: OneBoardShadow.sm.y)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                        .stroke(OneBoardColors.accent.opacity(0.08), lineWidth: 1)
                )
                .position(x: layer.rect.midX, y: layer.rect.minY - 44)
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

    private func handleKeyboardEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === canvasWindow else { return event }

        if viewModel.editingNumberLayerID != nil {
            if event.type == .keyDown, event.keyCode == 53 { viewModel.editingNumberLayerID = nil; return nil }
            return event
        }
        if viewModel.isTextInput || viewModel.editingTextLayerID != nil {
            if event.type == .keyDown, event.keyCode == 53 {
                if viewModel.isTextInput {
                    viewModel.cancelTextInput()
                } else {
                    viewModel.cancelEditText()
                }
                return nil
            }
            return event
        }

        if event.type == .flagsChanged {
            return handleFlagsChanged(event)
        }

        guard event.type == .keyDown else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)

        if isCommand, event.keyCode == 6 {
            if isShift {
                viewModel.redo()
            } else {
                viewModel.undo()
            }
            return nil
        }

        if isCommand, event.keyCode == 1 {
            onSave(renderedImage())
            return nil
        }

        switch event.keyCode {
        case 36, 76:
            onCopy(renderedImage())
            onClose()
            return nil
        case 53:
            onClose()
            return nil
        case 51, 117:
            guard viewModel.selectedTextLayerID != nil else { return event }
            viewModel.deleteSelectedTextLayer()
            return nil
        default:
            if viewModel.selectTool(forNumberKey: event.keyCode) {
                return nil
            }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 58 || event.keyCode == 61 else { return event }

        if pressedOptionKeyCodes.contains(event.keyCode) {
            pressedOptionKeyCodes.remove(event.keyCode)
            return nil
        }

        guard event.modifierFlags.contains(.option) else { return event }
        pressedOptionKeyCodes.insert(event.keyCode)

        if event.keyCode == 58 {
            viewModel.cycleColorBackward()
        } else {
            viewModel.incrementStyleValue()
        }
        return nil
    }

    private func renderedImage() -> NSImage {
        annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

/// 单个标注图层视图
struct AnnotationLayerView: View {
    let layer: AnnotationLayer
    let isSelected: Bool
    var mosaicImage: NSImage? = nil
    let onDoubleTap: () -> Void
    @State private var isHoveringText: Bool = false

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
        case .callout:
            if let target = layer.calloutRect {
                Path { path in
                    path.addRect(target)
                    let points = CalloutGeometry.connector(target: target, label: layer.rect)
                    path.move(to: points.start); path.addLine(to: points.end)
                    let angle = atan2(points.end.y - points.start.y, points.end.x - points.start.x)
                    for spread in [-CGFloat.pi / 7, CGFloat.pi / 7] {
                        path.move(to: points.end)
                        path.addLine(to: CGPoint(x: points.end.x - 12 * cos(angle + spread), y: points.end.y - 12 * sin(angle + spread)))
                    }
                }.stroke(Color(nsColor: layer.color), lineWidth: layer.lineWidth).allowsHitTesting(false)
            }
            textLayerView
        case .text:
            textLayerView
        case .number:
            numberLayerView
        case .mosaic:
            MosaicPreview(image: mosaicImage, rect: layer.rect, blockSize: layer.lineWidth)
                .frame(width: layer.rect.width, height: layer.rect.height)
                .position(x: layer.rect.midX, y: layer.rect.midY)
                .allowsHitTesting(false)
        }
    }

    private var textLayerView: some View {
        ZStack {
            Text(layer.text ?? "")
                .font(.system(size: layer.fontSize))
                .foregroundColor(Color(nsColor: layer.color))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(width: layer.rect.width, height: layer.rect.height, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: false)

            if isSelected {
                TextControlFrame(
                    rect: CGRect(origin: .zero, size: layer.rect.size),
                    color: Color(nsColor: layer.color),
                    showsHandles: true
                )
                .allowsHitTesting(false)
            } else if isHoveringText {
                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                    .stroke(Color(nsColor: layer.color).opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: layer.rect.width, height: layer.rect.height)
        .position(x: layer.rect.midX, y: layer.rect.midY)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringText = hovering
        }
    }

    private var numberLayerView: some View {
        let textColor = readableTextColor(for: layer.color)
        return ZStack {
            Circle()
                .fill(Color(nsColor: layer.color))
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: max(1, layer.lineWidth))
            Text("\(layer.numberValue ?? 0)")
                .font(.system(size: layer.fontSize, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(width: layer.rect.width, height: layer.rect.height)
        .position(x: layer.rect.midX, y: layer.rect.midY)
        .allowsHitTesting(false)
    }

    private func readableTextColor(for color: NSColor) -> Color {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}

private struct TextControlFrame: View {
    let rect: CGRect
    let color: Color
    let showsHandles: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                .stroke(color.opacity(0.8), lineWidth: 1.5)

            if showsHandles {
                ForEach(CanvasResizeHandle.allCases, id: \.self) { handle in
                    Rectangle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .position(handle.position(in: rect))
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
    }
}

private enum CanvasResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func resizedRect(from rect: CGRect, translation: CGSize, minSize: CGSize) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch self {
        case .topLeft:
            minX += translation.width
            minY += translation.height
        case .top:
            minY += translation.height
        case .topRight:
            maxX += translation.width
            minY += translation.height
        case .right:
            maxX += translation.width
        case .bottomRight:
            maxX += translation.width
            maxY += translation.height
        case .bottom:
            maxY += translation.height
        case .bottomLeft:
            minX += translation.width
            maxY += translation.height
        case .left:
            minX += translation.width
        }

        if maxX - minX < minSize.width {
            if adjustsLeftEdge {
                minX = maxX - minSize.width
            } else {
                maxX = minX + minSize.width
            }
        }

        if maxY - minY < minSize.height {
            if adjustsTopEdge {
                minY = maxY - minSize.height
            } else {
                maxY = minY + minSize.height
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var adjustsLeftEdge: Bool {
        self == .topLeft || self == .bottomLeft || self == .left
    }

    private var adjustsTopEdge: Bool {
        self == .topLeft || self == .top || self == .topRight
    }
}

private struct MosaicPreview: View {
    let image: NSImage?
    let rect: CGRect
    let blockSize: CGFloat
    var body: some View {
        if let image, let pixels = MosaicPixels.make(image: image, displaySize: image.size, rect: rect, blockSize: blockSize) {
            Image(decorative: pixels, scale: 1).interpolation(.none).resizable()
        } else {
            Rectangle().fill(Color.gray)
        }
    }
}

private struct NumberAnnotationEditor: View {
    @State var value: Int
    let maximum: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text("序号").font(.caption)
            TextField("序号", value: $value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 44).focused($focused)
                .onSubmit { if (1...maximum).contains(value) { onSave(value) } }
            Button { onCancel() } label: { Image(systemName: "xmark") }
            Button { onSave(value) } label: { Image(systemName: "checkmark") }
                .disabled(!(1...maximum).contains(value))
        }.buttonStyle(.borderless).padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1)))
            .help("输入 1 到 \(maximum)，其他序号自动调整")
            .onAppear { focused = true }
    }
}
