import SwiftUI
import AppKit
import ApplicationServices

/// 截图标注面板需要真正成为 key window，否则 SwiftUI TextField 会出现“看起来聚焦但无法输入”的问题。
private final class AnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum ScreenshotPresentationLayout {
    static func displayedSize(selectionRect: CGRect, visibleFrame: CGRect) -> CGSize {
        let selectedSize = selectionRect.size
        guard selectedSize.width > 0, selectedSize.height > 0 else { return .zero }
        let scale = min(
            visibleFrame.width * 0.9 / selectedSize.width,
            visibleFrame.height * 0.82 / selectedSize.height,
            1
        )
        return CGSize(width: selectedSize.width * scale, height: selectedSize.height * scale)
    }

    static func origin(selectionRect: CGRect, displayedSize: CGSize, scale: CGFloat) -> CGPoint {
        guard scale != 1 else { return selectionRect.origin }
        return CGPoint(
            x: selectionRect.midX - displayedSize.width / 2,
            y: selectionRect.midY - displayedSize.height / 2
        )
    }
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
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            print("[ScreenshotViewModel] 缺少屏幕录制权限，无法截图")
            PermissionManager.shared.promptScreenRecordingPermission()
            return
        }
        resetRecognitionState()
        closeActiveScreenshotSession()
        // WindowServer 合成是异步的。等待旧标注窗口真正离开屏幕后再抓取，
        // 否则连续截图时全屏图里会残留上一张窗口的模糊帧。
        await Task.yield()
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard let result = await captureService.captureRegion() else {
            print("[ScreenshotViewModel] 截图取消或失败")
            return
        }
        capturedImage = result.image
        switch ScreenshotLockedRoute.route(for: result.action) {
        case .annotation(let tool):
            showAnnotationWindow(result: result, initialTool: tool)
        case .copy:
            copyToClipboard(result.image)
        case .save:
            saveRenderedImageToDesktop(result.image)
        case .pin:
            pinToScreen(result.image, preferredFrame: result.selectionRect)
        case .ocr:
            await performOCR(on: result.image)
            OCRBubbleWindowManager.shared.show(text: ocrResult, relativeTo: result.selectionRect)
        case .translate:
            await performTranslation(on: result.image)
        case .longCapture:
            await captureLongScreenshot(from: result)
        }
    }

    private func captureLongScreenshot(from result: ScreenshotResult) async {
        isProcessing = true
        defer { isProcessing = false }
        guard let image = await LongScreenshotCaptureService().capture(initial: result.image, selectionRect: result.selectionRect) else { return }
        capturedImage = image
        showAnnotationWindow(result: ScreenshotResult(image: image, selectionRect: result.selectionRect), initialTool: .cursor)
    }

    /// 显示标注窗口（图片窗口 + 独立工具栏）
    private func showAnnotationWindow(result: ScreenshotResult, initialTool: AnnotationTool) {
        let image = result.image
        let selectionRect = result.selectionRect

        let annotationService = AnnotationService(baseImage: image)
        // 默认选中红色
        annotationService.selectedColor = .systemRed
        annotationService.selectedTool = initialTool
        let viewModel = AnnotationViewModel(annotationService: annotationService)

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selectionRect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? .zero
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        // NSImage 在 Retina 屏幕上可能报告像素尺寸；窗口必须使用框选区域的逻辑点尺寸。
        let displayedSize = ScreenshotPresentationLayout.displayedSize(
            selectionRect: selectionRect,
            visibleFrame: visibleFrame
        )
        let scale = selectionRect.width > 0 ? displayedSize.width / selectionRect.width : 1
        let imageWinWidth = displayedSize.width
        let imageWinHeight = displayedSize.height

        // 工具栏作为独立悬浮窗，0.5cm 间距
        let toolbarGap: CGFloat = 19 // ~0.5cm
        let toolbarHeight: CGFloat = 44

        // 图片窗口
        let hostingView = NSHostingView(
            rootView: AnnotationCanvasView(
                baseImage: image,
                displaySize: CGSize(width: imageWinWidth, height: imageWinHeight),
                annotationService: annotationService,
                viewModel: viewModel,
                onCopy: { [weak self] img in self?.copyToClipboard(img) },
                onSave: { [weak self] img in self?.saveRenderedImageToDesktop(img) },
                onPin: { [weak self] img in self?.pinToScreen(img, preferredFrame: self?.annotationWindow?.frame) },
                onOCR: { [weak self] img in
                    Task { await self?.performOCR(on: img) }
                },
                onTranslate: { [weak self] img in
                    Task { await self?.performTranslation(on: img) }
                },
                onClose: { [weak self] in
                    self?.closeActiveScreenshotSession()
                }
            )
        )

        let imageWindow = AnnotationPanel(
            contentRect: NSRect(x: 0, y: 0, width: imageWinWidth, height: imageWinHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // 标注画布覆盖在仍保留的框选遮罩上，视觉上始终停留在原截图页面。
        imageWindow.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
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
        // 未缩放时严格复用框选区域的原点，避免完成截图的一瞬间图片跳动。
        let imageOrigin = ScreenshotPresentationLayout.origin(
            selectionRect: selectionRect,
            displayedSize: CGSize(width: imageWinWidth, height: imageWinHeight),
            scale: scale
        )
        imageWindow.setFrameOrigin(imageOrigin)
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
                onSave: { [weak self] img in self?.saveRenderedImageToDesktop(img) },
                onPin: { [weak self] img in self?.pinToScreen(img, preferredFrame: self?.annotationWindow?.frame) },
                onOCR: { [weak self] img in
                    Task { await self?.performOCR(on: img) }
                },
                onTranslate: { [weak self] img in
                    Task { await self?.performTranslation(on: img) }
                },
                onClose: { [weak self] in
                    self?.closeActiveScreenshotSession()
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
        toolbarPanel.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
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
        windowFrameObserver = imageWindow.observe(\.frame, options: [.new]) { [weak self] window, _ in
            Task { @MainActor [weak self] in
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
        captureService.closeOverlay()
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


    func saveRenderedImageToDesktop(_ image: NSImage, date: Date = Date()) {
        guard let data = image.pngData else {
            print("[ScreenshotViewModel] PNG 数据生成失败")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let fileName = "OneBoard Screenshot \(formatter.string(from: date)).png"
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let fileURL = desktopURL.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
            print("[ScreenshotViewModel] 截图已保存到桌面: \(fileURL.path)")
        } catch {
            print("[ScreenshotViewModel] 保存到桌面失败: \(error)")
            saveToFile(image)
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
        // 初次挂载就提供截图逻辑尺寸，防止 hosting view 的理想尺寸参与缩放。
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
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

        await SelectedTextTranslation.run(
            hasPermission: PermissionManager.shared.hasAccessibilityPermission,
            requestPermission: { PermissionManager.shared.promptAccessibilityPermission() },
            readText: { [self] in
                if let text = await readSelectedTextViaAccessibility(), !text.isEmpty { return text }
                return await SelectedTextReader.readSelectedText()
            },
            translate: { TranslationPanelWindowManager.shared.show(sourceText: $0) }
        )
    }

    /// 通过辅助功能 API 读取前台应用选中的文字
    private func readSelectedTextViaAccessibility() async -> String? {
        await withCheckedContinuation { continuation in
            let systemWide = AXUIElementCreateSystemWide()
            var focusedApp: CFTypeRef?
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

            guard let app = focusedApp else {
                continuation.resume(returning: nil)
                return
            }

            var focusedElement: CFTypeRef?
            // AXUIElementCopyAttributeValue 返回的 CFTypeRef 在成功时总是 AXUIElement 类型
            AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

            guard let element = focusedElement else {
                continuation.resume(returning: nil)
                return
            }

            var selectedText: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

            if result == .success, let text = selectedText as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                continuation.resume(returning: nil)
            }
        }
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
enum SelectedTextReader {
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

/// 无权限先引导；没有选区不打开翻译窗口，也不显示失败提示。
@MainActor
enum SelectedTextTranslation {
    static func run(hasPermission: Bool, requestPermission: () -> Void,
                    readText: () async -> String, translate: (String) -> Void) async {
        guard hasPermission else { requestPermission(); return }
        let text = await readText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        translate(text)
    }
}
