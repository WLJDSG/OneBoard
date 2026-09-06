import AppKit
import SwiftUI

/// 标注工具栏（独立悬浮窗）
struct AnnotationToolbarView: View {
    @ObservedObject var annotationService: AnnotationService
    @ObservedObject var viewModel: AnnotationViewModel

    var onToolSelected: ((AnnotationTool) -> Void)? = nil
    let onComplete: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onPin: (NSImage) -> Void
    let onOCR: (NSImage) -> Void
    let onTranslate: (NSImage) -> Void
    let onClose: () -> Void
    let baseImage: NSImage
    let displaySize: CGSize

    @State private var showColorPicker: Bool = false

    private let toolShortcuts: [AnnotationTool: String] = [
        .cursor: "1",
        .rectangle: "2",
        .ellipse: "3",
        .arrow: "4",
        .line: "5",
        .text: "6",
        .number: "7",
        .mosaic: "8",
    ]

    var body: some View {
        HStack(spacing: 8) {
            toolGroup
            Divider().frame(height: 20)
            styleGroup
            Divider().frame(height: 20)
            historyGroup
            Divider().frame(height: 20)
            outputGroup
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OneBoardRadius.lg))
        .shadow(color: OneBoardShadow.lg.color, radius: OneBoardShadow.lg.radius, x: 0, y: OneBoardShadow.lg.y)
    }

    // MARK: - 工具组

    private var toolGroup: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
        }
        .padding(4)

    }

    // MARK: - 样式组

    private var styleGroup: some View {
        HStack(spacing: 7) {
            colorPickerButton

            Divider().frame(height: 22)

            Button(action: { annotationService.decrementStyleValue() }) {
                Image(systemName: "minus")
                    .oneBoardFont(.caption)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help("减小样式")

            Text(styleValueText)
                .oneBoardFont(.monoCaption)
                .frame(minWidth: 34)

            Button(action: { annotationService.incrementStyleValue() }) {
                Image(systemName: "plus")
                    .oneBoardFont(.caption)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help("增大样式 Right Option")

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)

    }

    private var styleValueText: String {
        switch annotationService.selectedTool {
        case .cursor:
            return "-"
        case .rectangle, .ellipse, .arrow, .line:
            return "\(Int(annotationService.lineWidth))"
        case .text:
            return "\(Int(annotationService.fontSize))"
        case .number:
            return "\(Int(annotationService.numberBadgeSize))"
        case .mosaic:
            return "\(Int(annotationService.mosaicBlockSize))"
        }
    }

    // MARK: - 历史操作组

    private var historyGroup: some View {
        HStack(spacing: 6) {
            iconActionButton("撤销 Cmd+Z", icon: "arrow.uturn.backward") {
                viewModel.undo()
            }
            .disabled(!annotationService.canUndo)

            iconActionButton("重做 Cmd+Shift+Z", icon: "arrow.uturn.forward") {
                viewModel.redo()
            }
            .disabled(!annotationService.canRedo)
        }
        .padding(4)

    }

    // MARK: - 输出操作组

    private var outputGroup: some View {
        HStack(spacing: 6) {
            iconActionButton("保存到桌面 Cmd+S", icon: "square.and.arrow.down") {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                onSave(rendered)
            }

            iconActionButton("贴图", icon: "pin") {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                onPin(rendered)
                onClose()
            }

            iconActionButton("OCR", icon: "text.viewfinder") {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                handleOCROutput(rendered)
            }

            Button {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                handleTranslationOutput(rendered)
            } label: {
                Label("翻译", systemImage: "character.bubble")
                    .font(OneBoardFont.callout)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .help("识别选区文字并翻译")

            iconActionButton("完成 Enter", icon: "checkmark", prominent: true) {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                onComplete(rendered)
            }

            iconActionButton("关闭 Esc", icon: "xmark", muted: true) {
                onClose()
            }
        }
        .padding(4)

    }

    func handleTranslationOutput(_ image: NSImage) {
        onTranslate(image)
    }

    func handleOCROutput(_ image: NSImage) {
        onOCR(image)
    }

    // MARK: - 工具按钮

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button(action: {
            annotationService.selectedTool = tool
            onToolSelected?(tool)
        }) {
            Image(systemName: tool.iconName)
                .oneBoardFont(.body)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: OneBoardRadius.sm).fill(
                        annotationService.selectedTool == tool
                            ? OneBoardColors.accent.opacity(0.15)
                            : Color.clear
                    )
                )
                .foregroundColor(
                    annotationService.selectedTool == tool ? OneBoardColors.accent : OneBoardColors.textPrimary
                )
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) \(toolShortcuts[tool] ?? "")")
    }

    // MARK: - 颜色选择按钮

    private var colorPickerButton: some View {
        Button(action: { showColorPicker.toggle() }) {
            Circle()
                .fill(Color(nsColor: annotationService.selectedColor))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 1.5)
                )
                .shadow(color: OneBoardShadow.sm.color, radius: OneBoardShadow.sm.radius, x: 0, y: OneBoardShadow.sm.y)
        }
        .buttonStyle(.plain)
        .help("选择颜色")
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) { colorPickerPopover }
    }

    // MARK: - 颜色选择弹窗

    private var colorPickerPopover: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 4), spacing: 6) {
                ForEach(annotationService.presetColors, id: \.self) { color in
                    Button(action: {
                        annotationService.selectedColor = color
                    }) {
                        RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                            .fill(Color(nsColor: color))
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                                    .stroke(Color.white, lineWidth: annotationService.selectedColor == color ? 2 : 0)
                            )
                            .shadow(color: OneBoardShadow.sm.color, radius: OneBoardShadow.sm.radius, x: 0, y: OneBoardShadow.sm.y)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Button(action: {
                showColorPicker = false
                showSystemColorPanel()
            }) {
                Label("更多颜色…", systemImage: "paintpalette")
                    .oneBoardFont(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
        .padding(12)
        .frame(width: 160)
    }

    private func showSystemColorPanel() {
        let panel = NSColorPanel.shared
        let coordinator = Coordinator(annotationService: annotationService)

        panel.color = annotationService.selectedColor
        panel.isContinuous = true
        panel.mode = .RGB

        objc_setAssociatedObject(panel, "colorCoordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        panel.setTarget(coordinator)
        panel.setAction(#selector(Coordinator.colorPanelDidChange(_:)))
        panel.orderFrontRegardless()
    }

    private class Coordinator: NSObject {
        weak var annotationService: AnnotationService?
        init(annotationService: AnnotationService) {
            self.annotationService = annotationService
        }
        @MainActor @objc func colorPanelDidChange(_ sender: NSColorPanel) {
            annotationService?.selectedColor = sender.color
        }
    }

    private func iconActionButton(
        _ label: String,
        icon: String,
        prominent: Bool = false,
        muted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(prominent ? OneBoardFont.headline : OneBoardFont.callout)
                .frame(width: prominent ? 34 : 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                        .fill(buttonBackgroundColor(prominent: prominent, muted: muted))
                )
                .foregroundColor(prominent ? .white : OneBoardColors.textPrimary.opacity(muted ? 0.55 : 0.78))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func buttonBackgroundColor(prominent: Bool, muted: Bool) -> Color {
        if prominent {
            return OneBoardColors.success
        }
        return OneBoardColors.accent.opacity(muted ? 0.06 : 0.10)
    }
}

// MARK: - OCR/翻译结果浮窗

@MainActor
final class AnnotationResultWindowManager {
    static let shared = AnnotationResultWindowManager()
    private var panel: NSPanel?

    private init() {}

    func close() {
        panel?.close()
        panel = nil
    }

    /// 在截图窗口右侧（或左侧）显示结果
    func show(title: String, text: String, relativeTo sourceFrame: NSRect? = nil) {
        let hostingView = NSHostingView(rootView: AnnotationResultView(title: title, text: text) { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        })

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView

        if let sourceFrame {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let panelFrame = panel.frame
            let gap: CGFloat = 38

            var x = sourceFrame.maxX + gap
            let y = sourceFrame.midY - panelFrame.height / 2

            if x + panelFrame.width > screenFrame.maxX {
                x = sourceFrame.minX - panelFrame.width - gap
            }
            if x < screenFrame.minX {
                x = screenFrame.maxX - panelFrame.width - 8
            }

            let clampedY = min(max(y, screenFrame.minY), screenFrame.maxY - panelFrame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: clampedY))
        } else {
            FloatingWindowManager.positionAtTopRight(panel, offset: 28)
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel?.close()
        self.panel = panel
    }
}

private struct AnnotationResultView: View {
    let title: String
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .oneBoardFont(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(text)
                    .oneBoardFont(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 320, height: 260)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
    }
}
