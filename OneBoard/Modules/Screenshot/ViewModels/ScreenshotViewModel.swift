import SwiftUI
import AppKit

/// 截图标注面板需要真正成为 key window，否则 SwiftUI TextField 会出现“看起来聚焦但无法输入”的问题。
private final class AnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

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

    /// 截图窗口（含图片和标注）
    private var annotationWindow: NSPanel?
    /// 工具栏独立悬浮窗
    private var toolbarPanel: NSPanel?
    /// 工具栏跟随用的 frame 观察
    private var windowFrameObserver: NSKeyValueObservation?

    private init() {}

    // MARK: - 截图流程

    /// 开始截图（快捷键触发）
    func startCapture() async {
        resetRecognitionState()
        closeActiveScreenshotSession()
        guard let result = await captureService.captureRegion() else {
            print("[ScreenshotViewModel] 截图取消或失败")
            return
        }
        capturedImage = result.image
        showAnnotationWindow(result: result)
    }

    /// 显示标注窗口（图片窗口 + 独立工具栏）
    private func showAnnotationWindow(result: ScreenshotResult) {
        let image = result.image
        let selectionRect = result.selectionRect

        let annotationService = AnnotationService(baseImage: image)
        // 默认选中红色
        annotationService.selectedColor = .systemRed
        let viewModel = AnnotationViewModel(annotationService: annotationService)

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let maxWidth = screenFrame.width * 0.9
        let maxHeight = screenFrame.height * 0.82

        // 图片窗口：只包含图片和标注，不含工具栏
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1.0)
        let imageWinWidth = image.size.width * scale
        let imageWinHeight = image.size.height * scale

        // 工具栏作为独立悬浮窗，0.5cm 间距
        let toolbarGap: CGFloat = 19 // ~0.5cm
        let toolbarHeight: CGFloat = 44

        // 图片窗口
        let hostingView = NSHostingView(
            rootView: AnnotationCanvasView(
                baseImage: image,
                annotationService: annotationService,
                viewModel: viewModel,
                onCopy: { [weak self] img in self?.copyToClipboard(img) },
                onSave: { [weak self] img in self?.saveToFile(img) },
                onPin: { [weak self] img in self?.pinToScreen(img, preferredFrame: self?.annotationWindow?.frame) },
                onOCR: { [weak self] img in
                    Task { await self?.performOCR(on: img) }
                },
                onTranslate: { [weak self] img in
                    Task { await self?.performTranslation(on: img) }
                },
                onClose: { [weak self] in
                    self?.closeAnnotationWindows()
                }
            )
        )

        let imageWindow = AnnotationPanel(
            contentRect: NSRect(x: 0, y: 0, width: imageWinWidth, height: imageWinHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        imageWindow.level = .floating
        imageWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        imageWindow.isFloatingPanel = true
        imageWindow.hidesOnDeactivate = false
        imageWindow.backgroundColor = .clear
        imageWindow.isOpaque = false
        imageWindow.hasShadow = true
        imageWindow.contentView = hostingView
        imageWindow.isMovableByWindowBackground = false
        viewModel.setWindow(imageWindow)

        // 定位图片窗口在框选区域
        let winX = min(max(selectionRect.midX - imageWinWidth / 2, screenFrame.minX),
                       screenFrame.maxX - imageWinWidth)
        let winY = min(max(selectionRect.midY - imageWinHeight / 2, screenFrame.minY),
                       screenFrame.maxY - imageWinHeight)
        imageWindow.setFrameOrigin(NSPoint(x: winX, y: winY))
        NSApp.activate(ignoringOtherApps: true)
        imageWindow.makeKeyAndOrderFront(nil)

        self.annotationWindow = imageWindow

        // 工具栏独立悬浮窗
        let toolbarHosting = NSHostingView(
            rootView: AnnotationToolbarView(
                annotationService: annotationService,
                viewModel: viewModel,
                onComplete: { [weak self] img in
                    self?.copyToClipboard(img)
                    self?.closeActiveScreenshotSession()
                },
                onSave: { [weak self] img in self?.saveToFile(img) },
                onPin: { [weak self] img in self?.pinToScreen(img, preferredFrame: self?.annotationWindow?.frame) },
                onOCR: { [weak self] img in
                    Task { await self?.performOCR(on: img) }
                },
                onTranslate: { [weak self] img in
                    Task { await self?.performTranslation(on: img) }
                },
                onClose: { [weak self] in
                    self?.closeAnnotationWindows()
                },
                baseImage: image,
                displaySize: CGSize(width: imageWinWidth, height: imageWinHeight)
            )
        )

        // 工具栏自适应宽度
        let toolbarNaturalWidth = toolbarHosting.fittingSize.width
        let toolbarWidth = max(toolbarNaturalWidth, imageWinWidth)

        let toolbarPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 工具栏 level 略高于图片窗口，确保可点击
        toolbarPanel.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        toolbarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        toolbarPanel.isFloatingPanel = true
        toolbarPanel.hidesOnDeactivate = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.isOpaque = false
        toolbarPanel.hasShadow = false
        toolbarPanel.contentView = toolbarHosting

        // 定位工具栏在图片窗口下方 0.5cm
        positionToolbar(toolbarPanel, below: imageWindow, gap: toolbarGap, screenFrame: screenFrame)

        toolbarPanel.orderFront(nil)
        // 确保工具栏在图片窗口之上（nonactivatingPanel 无法 makeKey，用 orderFrontRegardless）
        toolbarPanel.orderFrontRegardless()
        self.toolbarPanel = toolbarPanel

        // 监听图片窗口移动 → 工具栏跟随
        // 使用 assumeIsolated 断言已在主线程（frame KVO 回调保证在主线程），避免 Task 开销
        windowFrameObserver = imageWindow.observe(\.frame, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, let toolbar = self.toolbarPanel else { return }
                let sf = NSScreen.main?.visibleFrame ?? .zero
                self.positionToolbar(toolbar, below: window, gap: toolbarGap, screenFrame: sf)
            }
        }
    }

    /// 将工具栏定位在图片窗口下方，超出屏幕时自动偏移
    private func positionToolbar(_ toolbar: NSPanel, below imageWindow: NSWindow, gap: CGFloat, screenFrame: CGRect) {
        let imageFrame = imageWindow.frame
        let toolbarWidth = toolbar.frame.width
        let toolbarHeight = toolbar.frame.height

        // 默认：居中对齐图片窗口，下方 gap 处
        var toolbarX = imageFrame.midX - toolbarWidth / 2
        var toolbarY = imageFrame.minY - toolbarHeight - gap

        // 如果工具栏右侧超出屏幕，向左偏移
        if toolbarX + toolbarWidth > screenFrame.maxX {
            toolbarX = screenFrame.maxX - toolbarWidth - 8
        }
        // 如果左侧超出
        if toolbarX < screenFrame.minX {
            toolbarX = screenFrame.minX + 8
        }
        // 如果下方超出屏幕，放到图片上方
        if toolbarY < screenFrame.minY {
            toolbarY = imageFrame.maxY + gap
        }

        toolbar.setFrameOrigin(NSPoint(x: toolbarX, y: toolbarY))
    }

    private func closeAnnotationWindows() {
        windowFrameObserver?.invalidate()
        windowFrameObserver = nil
        annotationWindow?.makeFirstResponder(nil)
        annotationWindow?.close()
        annotationWindow = nil
        toolbarPanel?.close()
        toolbarPanel = nil
    }

    func closeActiveScreenshotSession() {
        closeAnnotationWindows()
        OCRBubbleWindowManager.shared.close()
        AnnotationResultWindowManager.shared.close()
        TranslationPanelWindowManager.shared.closePanel()
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

    func pinToScreen(_ image: NSImage, preferredFrame: NSRect? = nil) {
        let frame = preferredFrame ?? NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let panel = NSPanel(
            contentRect: frame,
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
        if preferredFrame == nil {
            FloatingWindowManager.centerWindow(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        pinnedWindows.append(panel)
    }

    // MARK: - OCR

    func performOCR(on image: NSImage) async {
        isProcessing = true
        ocrResult = ""
        defer { isProcessing = false }

        do {
            let recognizedText = try await recognizeText(in: image)
            if recognizedText.isEmpty {
                ocrResult = "未识别到文字"
            } else {
                ocrResult = recognizedText
            }
            print("[ScreenshotViewModel] OCR 完成: \(ocrResult.prefix(50))...")
        } catch {
            ocrResult = "OCR 识别失败: \(error.localizedDescription)"
            print("[ScreenshotViewModel] OCR 失败: \(error)")
        }
    }

    // MARK: - 翻译

    func performTranslation(on image: NSImage) async {
        isProcessing = true
        ocrResult = ""
        translationResult = ""
        defer { isProcessing = false }

        let text: String
        do {
            text = try await recognizeText(in: image)
            ocrResult = text.isEmpty ? "未识别到文字" : text
        } catch {
            ocrResult = "OCR 识别失败: \(error.localizedDescription)"
            translationResult = "翻译失败: \(error.localizedDescription)"
            print("[ScreenshotViewModel] 翻译前 OCR 失败: \(error)")
            return
        }

        guard !text.isEmpty else {
            translationResult = "没有可翻译的文字"
            AnnotationResultWindowManager.shared.show(
                title: "翻译",
                text: translationResult,
                relativeTo: annotationWindow?.frame
            )
            return
        }

        TranslationPanelWindowManager.shared.show(
            sourceText: text,
            relativeTo: annotationWindow?.frame
        )
    }

    /// 翻译当前前台应用中选中的文字
    func translateSelectedText() async {
        isProcessing = true
        ocrResult = ""
        translationResult = ""
        defer { isProcessing = false }

        let selectedText = await SelectedTextReader.readSelectedText()
        guard !selectedText.isEmpty else {
            translationResult = "没有检测到选中的文字"
            AnnotationResultWindowManager.shared.show(title: "翻译", text: translationResult)
            return
        }

        TranslationPanelWindowManager.shared.show(sourceText: selectedText)
    }

    private func resetRecognitionState() {
        ocrResult = ""
        translationResult = ""
    }

    private func recognizeText(in image: NSImage) async throws -> String {
        let language = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrLanguage) ?? "zh-Hans"
        let ocrService = OCRServiceFactory.create()
        return try await ocrService.recognizeText(in: image, language: language)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

@MainActor
private enum SelectedTextReader {
    static func readSelectedText() async -> String {
        await PasteboardMonitor.shared.performIgnoringChanges {
            await copySelectedText()
        }
    }

    private static func copySelectedText() async -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let originalChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        sendCopyShortcut()

        try? await Task.sleep(nanoseconds: 180_000_000)

        let copiedText: String
        if pasteboard.changeCount != originalChangeCount {
            copiedText = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            copiedText = ""
        }

        snapshot.restore(to: pasteboard)
        return copiedText
    }

    private static func sendCopyShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copy.setString(string, forType: type)
                }
            }
            return copy
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
