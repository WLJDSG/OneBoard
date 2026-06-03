import SwiftUI
import AppKit

/// 截图模块 ViewModel
@MainActor
final class ScreenshotViewModel: ObservableObject {
    static let shared = ScreenshotViewModel()

    @Published var capturedImage: NSImage?
    @Published var annotatedImage: NSImage?
    @Published var ocrResult: String = ""
    @Published var translationResult: String = ""
    @Published var isProcessing: Bool = false
    @Published var pinnedWindows: [NSWindow] = []

    private let captureService = ScreenshotCaptureService()
    private let ocrService = OCRServiceFactory.create()
    private let translationService = TranslationServiceFactory.create()

    private init() {}

    // MARK: - 截图流程

    /// 开始截图（快捷键触发）
    func startCapture() async {
        guard let image = await captureService.captureRegion() else {
            print("[ScreenshotViewModel] 截图取消或失败")
            return
        }
        capturedImage = image
        showAnnotationWindow(image: image)
    }

    /// 显示标注窗口
    private func showAnnotationWindow(image: NSImage) {
        let annotationService = AnnotationService(baseImage: image)
        let viewModel = AnnotationViewModel(annotationService: annotationService)

        let hostingView = NSHostingView(
            rootView: AnnotationCanvasView(
                baseImage: image,
                annotationService: annotationService,
                viewModel: viewModel,
                onCopy: { [weak self] img in
                    self?.copyToClipboard(img)
                },
                onSave: { [weak self] img in
                    self?.saveToFile(img)
                },
                onPin: { [weak self] img in
                    self?.pinToScreen(img)
                },
                onOCR: { [weak self] img in
                    Task { await self?.performOCR(on: img) }
                },
                onTranslate: { [weak self] img in
                    Task { await self?.performTranslation(on: img) }
                },
                onClose: { [weak viewModel] in
                    viewModel?.closeWindow()
                }
            )
        )

        let window = FloatingWindowManager.createFloatingPanel(
            contentView: hostingView,
            width: image.size.width + 60,
            height: image.size.height + 100,
            title: "截图标注"
        )
        FloatingWindowManager.centerWindow(window)
        window.makeKeyAndOrderFront(nil)
        viewModel.setWindow(window)
    }

    // MARK: - 操作

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(image.pngData, forType: .png)
        print("[ScreenshotViewModel] 截图已复制到剪贴板")
    }

    func saveToFile(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "截图_\(Date().shortDateString).png"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? image.pngData?.write(to: url)
                print("[ScreenshotViewModel] 截图已保存到: \(url.path)")
            }
        }
    }

    func pinToScreen(_ image: NSImage) {
        let hostingView = NSHostingView(
            rootView: PinnedScreenshotView(image: image)
        )

        let panel = FloatingWindowManager.createFloatingPanel(
            contentView: hostingView,
            width: image.size.width,
            height: image.size.height,
            title: "贴图"
        )

        // 贴图窗口置顶
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        FloatingWindowManager.centerWindow(panel)
        panel.makeKeyAndOrderFront(nil)
        pinnedWindows.append(panel)
    }

    // MARK: - OCR

    func performOCR(on image: NSImage) async {
        isProcessing = true
        defer { isProcessing = false }

        let language = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrLanguage) ?? "zh-Hans"

        do {
            ocrResult = try await ocrService.recognizeText(in: image, language: language)
            print("[ScreenshotViewModel] OCR 完成: \(ocrResult.prefix(50))...")
        } catch {
            ocrResult = "OCR 识别失败: \(error.localizedDescription)"
            print("[ScreenshotViewModel] OCR 失败: \(error)")
        }
    }

    // MARK: - 翻译

    func performTranslation(on image: NSImage) async {
        // 先 OCR 再翻译
        if ocrResult.isEmpty {
            await performOCR(on: image)
        }

        guard !ocrResult.isEmpty else {
            translationResult = "没有可翻译的文字"
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let targetLang = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.translationTargetLanguage) ?? "en"

        do {
            translationResult = try await translationService.translate(
                ocrResult,
                from: nil,
                to: targetLang
            )
            print("[ScreenshotViewModel] 翻译完成: \(translationResult.prefix(50))...")
        } catch {
            translationResult = "翻译失败: \(error.localizedDescription)"
            print("[ScreenshotViewModel] 翻译失败: \(error)")
        }
    }
}