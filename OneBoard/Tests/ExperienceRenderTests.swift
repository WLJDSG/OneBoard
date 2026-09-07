import AppKit
import SwiftUI
import XCTest
@testable import OneBoardKit

final class ExperienceRenderTests: XCTestCase {
    func testReducedMotionSkipsPanelTravelAndExitIsShorter() {
        XCTAssertEqual(InterfaceMotion.panelDuration(presenting: true, reduceMotion: true), 0)
        XCTAssertEqual(InterfaceMotion.panelDuration(presenting: false, reduceMotion: true), 0)
        XCTAssertLessThan(InterfaceMotion.panelDuration(presenting: false, reduceMotion: false),
                          InterfaceMotion.panelDuration(presenting: true, reduceMotion: false))
    }

    @MainActor
    func testCalendarAndStatusBackgroundsStayOpaqueInBothAppearances() throws {
        let requested = ProcessInfo.processInfo.environment["ONEBOARD_CARD_RENDER"]
        let directory = requested ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { if requested == nil { try? FileManager.default.removeItem(atPath: directory) } }
        let originalApps = MacStatusModel.shared.apps
        MacStatusModel.shared.apps = (1...3).map { AppNetworkUsage(id: "Preview.\($0)", name: "测试应用 \($0)", received: 30_000_000, sent: 2_000_000) }
        defer { MacStatusModel.shared.apps = originalApps }
        for dark in [false, true] {
            let calendar = try render(CalendarPanelView(), size: CGSize(width: 960, height: 590), dark: dark, path: directory + "/calendar-\(dark).png")
            let status = try render(MacStatusView(), size: CGSize(width: 400, height: 660), dark: dark, path: directory + "/status-\(dark).png")
            for bitmap in [calendar, status] {
                let background = try XCTUnwrap(bitmap.colorAt(x: 10, y: 10))
                XCTAssertEqual(background.alphaComponent, 1, accuracy: 0.01, "卡片底色必须隔离壁纸，避免背景影响文字对比")
            }
        }
    }

    @MainActor
    func testRenderStagingAndTextMosaicWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["ONEBOARD_STAGING_RENDER"] else { throw XCTSkip("按需输出暂存与截图样式") }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let image = NSImage(size: CGSize(width: 760, height: 400))
        image.lockFocus()
        NSColor.white.setFill(); CGRect(origin: .zero, size: image.size).fill()
        ("文件暂存与截图标注" as NSString).draw(at: CGPoint(x: 50, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
        ("原图像素 · 固定方格 · 拖动时不透明" as NSString).draw(at: CGPoint(x: 50, y: 140), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.darkGray])
        image.unlockFocus()
        let service = AnnotationService(baseImage: image)
        service.addText(in: CGRect(x: 50, y: 140, width: 320, height: 44), text: "已完成的文字没有边框", fontSize: 22)
        service.mosaicBlockSize = 10
        service.addMosaic(CGRect(x: 48, y: 230, width: 435, height: 38))
        let model = AnnotationViewModel(annotationService: service)
        model.isTextInput = true
        model.textInputRect = CGRect(x: 50, y: 310, width: 240, height: 40)
        let canvas = AnnotationCanvasView(baseImage: image, displaySize: image.size, annotationService: service, viewModel: model,
            onCopy: { _ in }, onSave: { _ in }, onPin: { _ in }, onOCR: { _ in }, onTranslate: { _ in }, onClose: {})
        try render(canvas, size: image.size, dark: false, path: directory + "/annotation.png")
        try render(NotchShelfView(viewModel: .shared), size: NotchShelfAnimationLayout.expandedSize, dark: true, path: directory + "/shelf.png")
        model.cancelTextInput()
        model.selectedTextLayerID = service.layers.first?.id
        try render(canvas, size: image.size, dark: false, path: directory + "/text-selected.png")
        model.enterTextEdit()
        try render(canvas, size: image.size, dark: false, path: directory + "/text-editing.png")
        for tool in [AnnotationTool.text, .mosaic, .arrow] {
            service.selectedTool = tool
            let toolbar = AnnotationToolbarView(annotationService: service, viewModel: model, onComplete: { _ in }, onSave: { _ in }, onPin: { _ in }, onOCR: { _ in }, onTranslate: { _ in }, onClose: {}, baseImage: image, displaySize: image.size)
            try render(toolbar, size: CGSize(width: 960, height: 80), dark: false, path: directory + "/refined-toolbar-\(tool.rawValue).png")
        }
    }

    @MainActor
    func testRenderChangedViewsWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["ONEBOARD_EXPERIENCE_RENDER"] else { throw XCTSkip("按需输出本次改动的界面") }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let image = NSImage(size: CGSize(width: 620, height: 380))
        image.lockFocus(); NSColor.white.setFill(); CGRect(origin: .zero, size: image.size).fill(); image.unlockFocus()
        let annotations = AnnotationService(baseImage: image)
        annotations.selectedTool = .text
        annotations.addCallout(target: CGRect(x: 40, y: 30, width: 150, height: 100), label: CGRect(x: 270, y: 230, width: 260, height: 50), text: "在这里输入标注文字")
        let model = AnnotationViewModel(annotationService: annotations)
        for dark in [false, true] {
            try render(ClaudeOAuthAccountView(onSave: { _ in }, onCancel: {}), size: CGSize(width: 560, height: 430), dark: dark, path: directory + "/claude-oauth-\(dark).png")
            let editor = AIProviderEditorView(client: .claude, profile: nil, savedAPIKey: nil, onSave: { _, _ in }, onSaveAndSwitch: { _, _ in }, onCancel: {})
            try render(editor, size: CGSize(width: 860, height: 820), dark: dark, path: directory + "/provider-\(dark).png")
            for tool in [AnnotationTool.cursor, .text, .callout, .number, .mosaic] {
                annotations.selectedTool = tool
                let toolbar = AnnotationToolbarView(annotationService: annotations, viewModel: model, onComplete: { _ in }, onSave: { _ in }, onPin: { _ in }, onOCR: { _ in }, onTranslate: { _ in }, onLongCapture: {}, onClose: {}, baseImage: image, displaySize: image.size)
                try render(toolbar, size: CGSize(width: 900, height: 80), dark: dark, path: directory + "/toolbar-\(tool.rawValue)-\(dark).png")
            }
        }
        let rendered = annotations.renderToImage(baseImage: image, displaySize: image.size)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory + "/callout.png"))
    }

    // 设置页会启动系统能力检查，单独进程渲染以免污染其他测试的应用生命周期。
    @MainActor
    func testRenderAccountAndAuthorizationWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["ONEBOARD_SETTINGS_RENDER"] else { throw XCTSkip("按需独立进程渲染设置页") }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "OneBoard.AccessVisualReview")!
        defer { defaults.removePersistentDomain(forName: "OneBoard.AccessVisualReview") }
        for dark in [false, true] {
            for tab in [SettingsTab.authorization, .claudeAccounts] {
                defaults.set(tab.rawValue, forKey: Constants.UserDefaultsKeys.selectedSettingsTab)
                try render(SettingsView().defaultAppStorage(defaults), size: CGSize(width: 1060, height: 760), dark: dark, path: directory + "/settings-\(tab.rawValue)-\(dark).png")
            }
        }
    }

    @MainActor
    @discardableResult
    private func render<V: View>(_ view: V, size: CGSize, dark: Bool, path: String) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        return bitmap
    }
}
