import AppKit
import SwiftUI
import XCTest
@testable import OneBoardKit

final class ExperienceRenderTests: XCTestCase {
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
    private func render<V: View>(_ view: V, size: CGSize, dark: Bool, path: String) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
