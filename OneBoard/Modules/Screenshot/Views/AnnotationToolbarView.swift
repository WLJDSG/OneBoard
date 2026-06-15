import AppKit
import SwiftUI

/// 标注工具栏（独立悬浮窗）
struct AnnotationToolbarView: View {
    @ObservedObject var annotationService: AnnotationService
    @ObservedObject var viewModel: AnnotationViewModel

    let onComplete: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onPin: (NSImage) -> Void
    let onOCR: (NSImage) -> Void
    let onTranslate: (NSImage) -> Void
    let onClose: () -> Void
    let baseImage: NSImage
    let displaySize: CGSize

    @State private var showColorPicker: Bool = false

    private let presetColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemPurple, .systemPink,
        .black, .white
    ]

    var body: some View {
        HStack(spacing: 8) {
            toolGroup
            colorGroup
            actionButtonsRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            colorPickerPopover
        }
    }

    private var toolGroup: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.045))
        )
    }

    private var colorGroup: some View {
        HStack(spacing: 7) {
            ForEach(presetColors, id: \.self) { color in
                colorSwatch(color)
            }

            Button(action: { showColorPicker.toggle() }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.06))
                    )
                    .foregroundColor(Color.black.opacity(0.74))
            }
            .buttonStyle(.plain)
            .help("更多颜色")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.045))
        )
    }

    // MARK: - 工具按钮

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button(action: {
            annotationService.selectedTool = tool
        }) {
            Image(systemName: tool.iconName)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(annotationService.selectedTool == tool
                              ? Color.black.opacity(0.1)
                              : Color.clear)
                )
                .foregroundColor(annotationService.selectedTool == tool
                                 ? Color.black
                                 : Color.black.opacity(0.76))
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
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
                .shadow(color: .black.opacity(0.15), radius: 1)
        }
        .buttonStyle(.plain)
        .help("选择颜色")
    }

    private func colorSwatch(_ color: NSColor) -> some View {
        Button(action: { annotationService.selectedColor = color }) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: annotationService.selectedColor == color ? 2.5 : 1)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(color == .white ? 0.22 : 0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 1)
        }
        .buttonStyle(.plain)
        .help("选择颜色")
    }

    // MARK: - 颜色选择弹窗

    private var colorPickerPopover: some View {
        VStack(spacing: 10) {
            // 预设颜色
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 4), spacing: 6) {
                ForEach(presetColors, id: \.self) { color in
                    Button(action: {
                        annotationService.selectedColor = color
                    }) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: color))
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.white, lineWidth: annotationService.selectedColor == color ? 2 : 0)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 1)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // 系统颜色选择器按钮
            Button(action: {
                showColorPicker = false
                showSystemColorPanel()
            }) {
                Label("更多颜色…", systemImage: "paintpalette")
                    .font(.system(size: 12))
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

        // 存储 coordinator 防止被释放
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

    // MARK: - 操作按钮

    private var actionButtonsRow: some View {
        HStack(spacing: 6) {
            iconActionButton("保存", icon: "square.and.arrow.down") {
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
                Task {
                    let vm = ScreenshotViewModel.shared
                    await vm.performOCR(on: rendered)
                    OCRBubbleWindowManager.shared.show(
                        text: vm.ocrResult,
                        relativeTo: NSApp.keyWindow?.frame
                    )
                }
            }

            iconActionButton("翻译", icon: "character.bubble") {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                Task {
                    let vm = ScreenshotViewModel.shared
                    await vm.performTranslation(on: rendered)
                }
            }

            iconActionButton("撤销", icon: "arrow.uturn.backward") {
                viewModel.undo()
            }
            .disabled(annotationService.layers.isEmpty)

            iconActionButton("完成", icon: "checkmark", prominent: true) {
                let rendered = annotationService.renderToImage(baseImage: baseImage, displaySize: displaySize)
                onComplete(rendered)
            }

            iconActionButton("关闭", icon: "xmark", muted: true) {
                onClose()
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.045))
        )
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
                .font(.system(size: prominent ? 14 : 12, weight: prominent ? .bold : .regular))
                .frame(width: prominent ? 34 : 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: prominent ? 9 : 8)
                        .fill(buttonBackgroundColor(prominent: prominent, muted: muted))
                )
                .foregroundColor(prominent ? .white : Color.black.opacity(muted ? 0.55 : 0.78))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func buttonBackgroundColor(prominent: Bool, muted: Bool) -> Color {
        if prominent {
            return Color(nsColor: .systemGreen)
        }
        return Color.black.opacity(muted ? 0.03 : 0.06)
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

        // 定位在截图窗口右侧 1cm 处
        if let sourceFrame {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let panelFrame = panel.frame
            let gap: CGFloat = 38 // ~1cm

            // 优先放在右侧
            var x = sourceFrame.maxX + gap
            let y = sourceFrame.midY - panelFrame.height / 2

            // 如果右侧超出屏幕，放到左侧
            if x + panelFrame.width > screenFrame.maxX {
                x = sourceFrame.minX - panelFrame.width - gap
            }
            // 如果左侧也超出，贴着屏幕右边缘
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
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.black.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 320, height: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
