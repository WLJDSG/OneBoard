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
    private init() {}

    // MARK: - 截图流程

    /// 截图前记录的鼠标位置（用于窗口定位）
    private var captureStartMouseLocation: CGPoint = .zero

    /// 开始截图（快捷键触发）
    func startCapture() async {
        // 录制截图开始时的鼠标位置，用于窗口定位
        captureStartMouseLocation = NSEvent.mouseLocation

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

        // 限制窗口最大尺寸，不超过屏幕的 90%，下方预留悬浮工具栏。
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let maxWidth = screenFrame.width * 0.9
        let maxHeight = screenFrame.height * 0.82

        // 工具栏最小宽度（保证工具栏按钮完整显示）
        let toolbarMinWidth: CGFloat = 460

        let scale = min(maxWidth / image.size.width, (maxHeight - 44) / image.size.height, 1.0)
        let windowWidth = max(image.size.width * scale, toolbarMinWidth)
        let windowHeight = image.size.height * scale + 44

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = hostingView
        window.isMovableByWindowBackground = false

        // 窗口定位：使用截图开始时的鼠标位置，保证窗口出现在勾选区域附近
        let mouseLoc = captureStartMouseLocation
        var winX = mouseLoc.x - windowWidth / 2
        var winY = mouseLoc.y - windowHeight - 40

        // 边界检查：确保窗口和工具栏不超出屏幕
        winX = min(max(winX, screenFrame.minX), screenFrame.maxX - windowWidth)
        winY = min(max(winY, screenFrame.minY), screenFrame.maxY - windowHeight)

        window.setFrameOrigin(NSPoint(x: winX, y: winY))
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
        savePanel.level = .screenSaver
        NSApp.activate(ignoringOtherApps: true)

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            try? image.pngData?.write(to: url)
            print("[ScreenshotViewModel] 截图已保存到: \(url.path)")
        }
    }

    func pinToScreen(_ image: NSImage) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: PinnedScreenshotView(image: image) { [weak self, weak panel] in
                panel?.close()
                if let panel {
                    self?.pinnedWindows.removeAll { $0 === panel }
                }
            }
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
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
            let ocrService = OCRServiceFactory.create()
            ocrResult = try await ocrService.recognizeText(in: image, language: language)
            if ocrResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ocrResult = "未识别到文字"
            }
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
            let translationService = TranslationServiceFactory.create()
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
