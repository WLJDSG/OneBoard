import AppKit
import SwiftUI
import XCTest
@testable import OneBoardKit

/// 手动视觉验收：ONEBOARD_RENDER_DIRECTORY=/tmp/... swift test --filter FeaturePanelRenderTests
final class FeaturePanelRenderTests: XCTestCase {
    @MainActor
    func testRenderPanelsWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["ONEBOARD_RENDER_DIRECTORY"] else {
            throw XCTSkip("设置 ONEBOARD_RENDER_DIRECTORY 后输出视觉验收图片")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "OneBoard.VisualReview")!
        defer { defaults.removePersistentDomain(forName: "OneBoard.VisualReview") }
        let originalFiles = FileStagingViewModel.shared.stagedFiles
        let originalTodos = TodoListViewModel.shared.activeItems
        let originalApps = MacStatusModel.shared.apps
        MacStatusModel.shared.apps = (1...3).map { AppNetworkUsage(id: "Preview.\($0)", name: "测试应用 \($0)", received: 30_000_000, sent: 2_000_000) }
        defer {
            FileStagingViewModel.shared.stagedFiles = originalFiles
            TodoListViewModel.shared.activeItems = originalTodos
            MacStatusModel.shared.apps = originalApps
        }
        let model = TranslationPanelViewModel(sourceText: "让桌面上的每一步，更轻松。\nKeep your tools close and your workspace clear.")
        model.translatedText = "Make every step on your desktop easier.\n让工具触手可及，让工作空间井然有序。"
        for dark in [false, true] {
            let screenshot = NSImage(size: CGSize(width: 300, height: 200))
            let annotations = AnnotationService(baseImage: screenshot)
            let views: [(String, AnyView, CGSize)] = [
                ("shortcut-bindings", AnyView(QuickLaunchSettingsView().padding(16).background(Color(nsColor: .windowBackgroundColor))), CGSize(width: 720, height: 460)),
                ("menu-icons", AnyView(HStack(spacing: 16) {
                    Image(nsImage: MenuBarManager.menuSymbol("square.stack.3d.up")!)
                    Image(nsImage: MenuBarManager.menuSymbol("calendar")!)
                    Image(nsImage: MenuBarManager.networkImage(upload: 125_000, download: 3_500_000))
                }.padding(16).background(Color(nsColor: .windowBackgroundColor))), CGSize(width: 180, height: 50)),
                ("screenshot-toolbar", AnyView(AnnotationToolbarView(annotationService: annotations, viewModel: AnnotationViewModel(annotationService: annotations), onComplete: { _ in }, onSave: { _ in }, onPin: { _ in }, onOCR: { _ in }, onTranslate: { _ in }, onLongCapture: {}, onClose: {}, baseImage: screenshot, displaySize: screenshot.size)), CGSize(width: 820, height: 80)),
                ("ocr", AnyView(OCRBubbleView(text: "识别结果支持选中、编辑和复制。\nOCR keeps the original text available for review.", panelSize: CGSize(width: 440, height: 320), onClose: {})), CGSize(width: 440, height: 320)),
                ("translation", AnyView(TranslationPanelView(viewModel: model, onTranslate: {}, onSelectService: { _ in }, onClose: {})), CGSize(width: 520, height: 600)),
                ("gateway", AnyView(GatewaySwitcherPanelView()), GatewaySwitcherPanelLayout.size),
                ("files", AnyView(FileStagingView(viewModel: .shared, onClose: {})), FileStagingViewModel.shelfSize),
                ("clipboard", AnyView(ClipboardPopoverView()), CGSize(width: 920, height: 680)),
                ("calendar", AnyView(CalendarPanelView()), CGSize(width: 960, height: 590)),
                ("mac-status", AnyView(MacStatusView()), CGSize(width: 400, height: 600)),
                ("notch", AnyView(NotchShelfView(viewModel: .shared)), CGSize(width: 440, height: 220)),
                ("todo", AnyView(TodoSlidePanelView()), TodoSlidePanelWindowManager.panelSize),
                ("history", AnyView(TodoHistoryView()), CGSize(width: 360, height: 440))
            ]
            for (name, view, size) in views {
                try render(view.defaultAppStorage(defaults), size: size, dark: dark, path: "\(directory)/\(name)-\(dark ? "dark" : "light").png")
            }
            try render(TranslationPanelView(viewModel: model, onTranslate: {}, onSelectService: { _ in }, onClose: {}), size: CGSize(width: 520, height: 480), dark: dark, path: "\(directory)/translation-minimum-\(dark ? "dark" : "light").png")
            model.errorMessage = String(repeating: "HTTP 503：上游暂时不可用，请稍后重试。", count: 8)
            try render(TranslationPanelView(viewModel: model, onTranslate: {}, onSelectService: { _ in }, onClose: {}), size: CGSize(width: 520, height: 480), dark: dark, path: "\(directory)/translation-error-\(dark ? "dark" : "light").png")
            model.errorMessage = nil
            defaults.set(SettingsTab.files.rawValue, forKey: Constants.UserDefaultsKeys.selectedSettingsTab)
            try render(SettingsView().defaultAppStorage(defaults), size: CGSize(width: 960, height: 680), dark: dark, path: "\(directory)/settings-minimum-\(dark ? "dark" : "light").png")
            let url = URL(fileURLWithPath: directory).appendingPathComponent("季度项目交付与设计验收记录.txt")
            try Data("Preview only".utf8).write(to: url)
            var file = try StagedFile(url: url)
            file.id = 1
            file.thumbnailData = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?.tiffRepresentation
            FileStagingViewModel.shared.stagedFiles = [file]
            TodoListViewModel.shared.activeItems = [TodoItem(id: 1, text: "核对翻译结果并整理交付文档", priority: .high), TodoItem(id: 2, text: "检查深浅色模式和较长内容的显示效果", priority: .medium)]
            try render(FileStagingView(viewModel: .shared, onClose: {}), size: FileStagingViewModel.shelfSize, dark: dark, path: "\(directory)/files-content-\(dark ? "dark" : "light").png")
            try render(TodoSlidePanelView(), size: TodoSlidePanelWindowManager.panelSize, dark: dark, path: "\(directory)/todo-content-\(dark ? "dark" : "light").png")
            let rows = VStack(spacing: 12) {
                ForEach(TodoListViewModel.shared.activeItems) { item in
                    TodoRowView(item: item, isFadingOut: false, isCompleting: false, onToggleComplete: {}, onDelete: {}, onPriorityChange: { _ in })
                }
            }.padding(16).featurePanelStyle()
            try render(rows, size: CGSize(width: 340, height: 180), dark: dark, path: "\(directory)/todo-rows-\(dark ? "dark" : "light").png")
            FileStagingViewModel.shared.stagedFiles = originalFiles
            TodoListViewModel.shared.activeItems = originalTodos
            for tab in SettingsTab.allCases {
                defaults.set(tab.rawValue, forKey: Constants.UserDefaultsKeys.selectedSettingsTab)
                try render(SettingsView().defaultAppStorage(defaults), size: CGSize(width: 1060, height: 760), dark: dark, path: "\(directory)/settings-\(tab.rawValue)-\(dark ? "dark" : "light").png")
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
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }
}
