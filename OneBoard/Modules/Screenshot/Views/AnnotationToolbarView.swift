import SwiftUI

/// 标注工具栏
struct AnnotationToolbarView: View {
    @ObservedObject var annotationService: AnnotationService
    @ObservedObject var viewModel: AnnotationViewModel

    let onCopy: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onPin: (NSImage) -> Void
    let onOCR: (NSImage) -> Void
    let onTranslate: (NSImage) -> Void
    let onClose: () -> Void
    let baseImage: NSImage

    var body: some View {
        VStack(spacing: 0) {
            // 工具按钮行（可横向滚动，适应窄窗口）
            ScrollView(.horizontal, showsIndicators: false) {
                toolButtonsRow
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .frame(minWidth: 200, maxWidth: .infinity)
    }

    // MARK: - 工具按钮行

    private var toolButtonsRow: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            Divider()
                .frame(height: 24)
                .overlay(Color.black.opacity(0.12))

            colorPickerRow

            Divider()
                .frame(height: 24)
                .overlay(Color.black.opacity(0.12))

            actionButtonsRow

            // 撤销
            Button(action: { viewModel.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("撤销")
            .disabled(annotationService.layers.isEmpty)
        }
    }

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

    // MARK: - 颜色选择行

    private var colorPickerRow: some View {
        HStack(spacing: 5) {
            ForEach(annotationColors, id: \.self) { color in
                Button(action: {
                    annotationService.selectedColor = color
                }) {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .opacity(annotationService.selectedColor == color ? 1 : 0)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private let annotationColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .systemPurple,
        .white, .black
    ]

    // MARK: - 操作按钮行

    private var actionButtonsRow: some View {
        HStack(spacing: 6) {
            iconActionButton("复制", icon: "doc.on.doc") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                onCopy(rendered)
            }

            iconActionButton("保存", icon: "square.and.arrow.down") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                onSave(rendered)
            }

            iconActionButton("贴图", icon: "pin") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                onPin(rendered)
                onClose()
            }

            iconActionButton("OCR", icon: "text.viewfinder") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                Task {
                    let vm = ScreenshotViewModel.shared
                    await vm.performOCR(on: rendered)
                    await AnnotationResultWindowManager.shared.show(title: "文字识别", text: vm.ocrResult)
                }
            }

            iconActionButton("翻译", icon: "character.bubble") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                Task {
                    let vm = ScreenshotViewModel.shared
                    await vm.performTranslation(on: rendered)
                    await AnnotationResultWindowManager.shared.show(title: "翻译", text: vm.translationResult)
                }
            }

            Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.black.opacity(0.58))
            }
            .buttonStyle(.plain)
        }
    }

    private func iconActionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.05))
            )
            .foregroundColor(Color.black.opacity(0.78))
        }
        .buttonStyle(.plain)
        .help(label)
    }

}

@MainActor
final class AnnotationResultWindowManager {
    static let shared = AnnotationResultWindowManager()
    private var panel: NSPanel?

    private init() {}

    func show(title: String, text: String) {
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
        FloatingWindowManager.positionAtTopRight(panel, offset: 28)
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
