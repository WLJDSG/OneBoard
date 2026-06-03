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

    @State private var showOCRResult: Bool = false
    @State private var showTranslationResult: Bool = false
    @State private var ocrText: String = ""
    @State private var translatedText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 工具按钮行
            toolButtonsRow

            Divider()

            // 颜色选择行
            colorPickerRow

            Divider()

            // 操作按钮行
            actionButtonsRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )

        // OCR 结果弹窗
        .sheet(isPresented: $showOCRResult) {
            resultSheet(title: "OCR 识别结果", text: ocrText)
        }

        // 翻译结果弹窗
        .sheet(isPresented: $showTranslationResult) {
            resultSheet(title: "翻译结果", text: translatedText)
        }
    }

    // MARK: - 工具按钮行

    private var toolButtonsRow: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            Spacer()

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
                              ? OneBoardColors.primary.opacity(0.2)
                              : Color.clear)
                )
                .foregroundColor(annotationService.selectedTool == tool
                                 ? OneBoardColors.primary
                                 : OneBoardColors.textPrimary)
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }

    // MARK: - 颜色选择行

    private var colorPickerRow: some View {
        HStack(spacing: 6) {
            Text("颜色:")
                .font(.system(size: 11))
                .foregroundColor(OneBoardColors.textSecondary)

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
            actionButton("复制", icon: "doc.on.doc") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                onCopy(rendered)
            }

            actionButton("保存", icon: "square.and.arrow.down") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                onSave(rendered)
            }

            actionButton("贴图", icon: "pin") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                onPin(rendered)
            }

            actionButton("OCR", icon: "text.viewfinder") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                Task {
                    let vm = ScreenshotViewModel.shared
                    await vm.performOCR(on: rendered)
                    ocrText = vm.ocrResult
                    showOCRResult = true
                }
            }

            actionButton("翻译", icon: "character.bubble") {
                let rendered = annotationService.renderToImage(baseImage: baseImage)
                Task {
                    let vm = ScreenshotViewModel.shared
                    await vm.performTranslation(on: rendered)
                    translatedText = vm.translationResult
                    showTranslationResult = true
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(OneBoardColors.primary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 结果弹窗

    private func resultSheet(title: String, text: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    showOCRResult = false
                    showTranslationResult = false
                }
            }
            .padding()

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .frame(width: 400, height: 300)
    }
}