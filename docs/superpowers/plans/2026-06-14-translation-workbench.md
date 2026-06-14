# Translation Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-text translation result popup with a compact draggable translation workbench that shows editable source text, translated text, per-window language selectors, manual retranslation, language swap, and copy controls.

**Architecture:** Add a dedicated translation panel view model and SwiftUI panel view instead of overloading the existing OCR result popup. Screenshot translation and selected-text translation both open the same panel with source text; the panel performs the initial automatic translation and all later manual retranslation. Language changes inside the panel are local to that panel and do not write to UserDefaults.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit `NSPanel`, XCTest, existing `TranslationServiceProtocol`, existing UserDefaults keys for default source/target language.

---

## File Structure

- Create `OneBoard/Modules/Screenshot/Models/TranslationLanguage.swift`: language catalog, display names, default loading helpers, and swap behavior constraints.
- Create `OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift`: `@MainActor ObservableObject` for source text, translated text, language state, loading/error state, retranslate, swap, and copy.
- Create `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`: compact top-to-bottom workbench UI. It must not include instructional helper text such as “拖拽此区域移动”.
- Create `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`: AppKit panel creation, positioning, top-title drag support, and lifecycle.
- Modify `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`: route screenshot translation and selected-text translation into the new window manager.
- Modify `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`: remove translation result popup usage for translation and let the view model open the new workbench.
- Test `OneBoard/Tests/TranslationPanelViewModelTests.swift`: view model behavior without network via a fake translation service.
- Leave `AnnotationResultWindowManager` in `AnnotationToolbarView.swift` for OCR text result display only.
- Update `开发日志/2026-06/2026-06-14.md` after implementation.

## Task 1: Add Translation Language Model

**Files:**
- Create: `OneBoard/Modules/Screenshot/Models/TranslationLanguage.swift`
- Test: `OneBoard/Tests/TranslationPanelViewModelTests.swift`

- [ ] **Step 1: Write failing language model tests**

Create `OneBoard/Tests/TranslationPanelViewModelTests.swift` with:

```swift
import XCTest
@testable import OneBoard

final class TranslationPanelViewModelTests: XCTestCase {
    func testAutoLanguageCannotBeUsedAsTarget() {
        XCTAssertTrue(TranslationLanguage.sourceOptions.contains(.auto))
        XCTAssertFalse(TranslationLanguage.targetOptions.contains(.auto))
    }

    func testLanguageDisplayNamesMatchPanelLabels() {
        XCTAssertEqual(TranslationLanguage.auto.displayName, "自动检测")
        XCTAssertEqual(TranslationLanguage.english.displayName, "英文")
        XCTAssertEqual(TranslationLanguage.simplifiedChinese.displayName, "中文（简体）")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: FAIL because `TranslationLanguage` does not exist.

- [ ] **Step 3: Implement language model**

Create `OneBoard/Modules/Screenshot/Models/TranslationLanguage.swift`:

```swift
import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable, Equatable {
    case auto = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .english: return "英文"
        case .simplifiedChinese: return "中文（简体）"
        case .traditionalChinese: return "中文（繁体）"
        case .japanese: return "日文"
        case .korean: return "韩文"
        case .french: return "法文"
        case .german: return "德文"
        }
    }

    static let sourceOptions: [TranslationLanguage] = [
        .auto, .english, .simplifiedChinese, .traditionalChinese, .japanese, .korean, .french, .german
    ]

    static let targetOptions: [TranslationLanguage] = [
        .english, .simplifiedChinese, .traditionalChinese, .japanese, .korean, .french, .german
    ]

    static func sourceDefault(from defaults: UserDefaults = .standard) -> TranslationLanguage {
        let code = defaults.string(forKey: Constants.UserDefaultsKeys.translationSourceLanguage) ?? ""
        return sourceOptions.first { $0.rawValue == code } ?? .auto
    }

    static func targetDefault(from defaults: UserDefaults = .standard) -> TranslationLanguage {
        let code = defaults.string(forKey: Constants.UserDefaultsKeys.translationTargetLanguage) ?? "en"
        let language = targetOptions.first { $0.rawValue == code } ?? .english
        return language == .auto ? .english : language
    }
}
```

- [ ] **Step 4: Run tests to verify language model passes**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: PASS for the two language model tests.

## Task 2: Add Translation Panel ViewModel

**Files:**
- Modify: `OneBoard/Tests/TranslationPanelViewModelTests.swift`
- Create: `OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift`

- [ ] **Step 1: Add failing view model tests**

Append to `TranslationPanelViewModelTests`:

```swift
@MainActor
func testInitialTranslateUsesDefaultLanguagesWithoutSavingTemporaryChanges() async {
    let defaults = UserDefaults(suiteName: "translation-panel-tests-\(UUID().uuidString)")!
    defaults.set("zh-Hans", forKey: Constants.UserDefaultsKeys.translationSourceLanguage)
    defaults.set("en", forKey: Constants.UserDefaultsKeys.translationTargetLanguage)
    let service = FakeTranslationService()
    service.result = "Publish"

    let viewModel = TranslationPanelViewModel(
        sourceText: "发布",
        translationService: service,
        defaults: defaults
    )

    await viewModel.translate()
    viewModel.sourceLanguage = .japanese
    viewModel.targetLanguage = .korean

    XCTAssertEqual(service.requests.first?.sourceLanguage, "zh-Hans")
    XCTAssertEqual(service.requests.first?.targetLanguage, "en")
    XCTAssertEqual(viewModel.translatedText, "Publish")
    XCTAssertEqual(defaults.string(forKey: Constants.UserDefaultsKeys.translationSourceLanguage), "zh-Hans")
    XCTAssertEqual(defaults.string(forKey: Constants.UserDefaultsKeys.translationTargetLanguage), "en")
}

@MainActor
func testManualRetranslateUsesEditedSourceTextAndCurrentPanelLanguages() async {
    let defaults = UserDefaults(suiteName: "translation-panel-tests-\(UUID().uuidString)")!
    let service = FakeTranslationService()
    service.result = "Published"
    let viewModel = TranslationPanelViewModel(
        sourceText: "发布",
        translationService: service,
        defaults: defaults
    )

    viewModel.sourceText = "已发布"
    viewModel.sourceLanguage = .simplifiedChinese
    viewModel.targetLanguage = .english
    await viewModel.translate()

    XCTAssertEqual(service.requests.last?.text, "已发布")
    XCTAssertEqual(service.requests.last?.sourceLanguage, "zh-Hans")
    XCTAssertEqual(service.requests.last?.targetLanguage, "en")
    XCTAssertEqual(viewModel.translatedText, "Published")
}

@MainActor
func testSwapLanguagesMovesTranslatedTextIntoSourceWhenSourceIsNotAuto() async {
    let service = FakeTranslationService()
    let viewModel = TranslationPanelViewModel(
        sourceText: "发布",
        translationService: service,
        defaults: UserDefaults(suiteName: "translation-panel-tests-\(UUID().uuidString)")!
    )
    viewModel.sourceLanguage = .simplifiedChinese
    viewModel.targetLanguage = .english
    viewModel.translatedText = "Publish"

    viewModel.swapLanguages()

    XCTAssertEqual(viewModel.sourceLanguage, .english)
    XCTAssertEqual(viewModel.targetLanguage, .simplifiedChinese)
    XCTAssertEqual(viewModel.sourceText, "Publish")
    XCTAssertEqual(viewModel.translatedText, "发布")
}

@MainActor
func testTranslationFailureKeepsSourceTextAndShowsError() async {
    let service = FakeTranslationService()
    service.error = TranslationServiceError.translationFailed("网络异常")
    let viewModel = TranslationPanelViewModel(
        sourceText: "发布",
        translationService: service,
        defaults: UserDefaults(suiteName: "translation-panel-tests-\(UUID().uuidString)")!
    )

    await viewModel.translate()

    XCTAssertEqual(viewModel.sourceText, "发布")
    XCTAssertEqual(viewModel.translatedText, "")
    XCTAssertEqual(viewModel.errorMessage, "网络异常")
    XCTAssertFalse(viewModel.isTranslating)
}

private final class FakeTranslationService: TranslationServiceProtocol {
    struct Request {
        let text: String
        let sourceLanguage: String?
        let targetLanguage: String
    }

    var result = ""
    var error: Error?
    private(set) var requests: [Request] = []

    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        requests.append(Request(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
        if let error {
            throw error
        }
        return result
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: FAIL because `TranslationPanelViewModel` does not exist.

- [ ] **Step 3: Implement view model**

Create `OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift`:

```swift
import AppKit
import Foundation

@MainActor
final class TranslationPanelViewModel: ObservableObject {
    @Published var sourceText: String
    @Published var translatedText: String = ""
    @Published var sourceLanguage: TranslationLanguage
    @Published var targetLanguage: TranslationLanguage
    @Published var isTranslating = false
    @Published var errorMessage: String?

    private let translationService: TranslationServiceProtocol

    init(
        sourceText: String,
        translationService: TranslationServiceProtocol = TranslationServiceFactory.create(),
        defaults: UserDefaults = .standard
    ) {
        self.sourceText = sourceText
        self.translationService = translationService
        self.sourceLanguage = TranslationLanguage.sourceDefault(from: defaults)
        self.targetLanguage = TranslationLanguage.targetDefault(from: defaults)
    }

    func translate() async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            translatedText = ""
            errorMessage = "没有可翻译的文字"
            return
        }

        isTranslating = true
        errorMessage = nil
        defer { isTranslating = false }

        do {
            translatedText = try await translationService.translate(
                text,
                from: sourceLanguage == .auto ? nil : sourceLanguage.rawValue,
                to: targetLanguage.rawValue
            )
        } catch {
            translatedText = ""
            errorMessage = error.localizedDescription
        }
    }

    func swapLanguages() {
        guard sourceLanguage != .auto else { return }
        let previousSourceLanguage = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = previousSourceLanguage

        let previousSourceText = sourceText
        sourceText = translatedText
        translatedText = previousSourceText
        errorMessage = nil
    }

    func copyTranslatedText() {
        guard !translatedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
    }
}
```

- [ ] **Step 4: Run tests to verify view model passes**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: PASS.

## Task 3: Build Translation Panel Window and Drag Title Bar

**Files:**
- Create: `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`
- Create: `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`

- [ ] **Step 1: Create draggable title bar bridge**

Create `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`:

```swift
import AppKit
import SwiftUI

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TranslationPanelDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct TranslationPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> TranslationPanelDragView {
        TranslationPanelDragView()
    }

    func updateNSView(_ nsView: TranslationPanelDragView, context: Context) {}
}

@MainActor
final class TranslationPanelWindowManager {
    static let shared = TranslationPanelWindowManager()

    private var panel: NSPanel?

    private init() {}

    func show(sourceText: String, relativeTo sourceFrame: NSRect? = nil) {
        let viewModel = TranslationPanelViewModel(sourceText: sourceText)
        let hostingView = NSHostingView(
            rootView: TranslationPanelView(viewModel: viewModel) { [weak self] in
                self?.panel?.close()
                self?.panel = nil
            }
        )

        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.borderless],
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

        position(panel, relativeTo: sourceFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel?.close()
        self.panel = panel

        Task { await viewModel.translate() }
    }

    private func position(_ panel: NSPanel, relativeTo sourceFrame: NSRect?) {
        if let sourceFrame {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let gap: CGFloat = 38
            var x = sourceFrame.maxX + gap
            let y = sourceFrame.midY - panel.frame.height / 2

            if x + panel.frame.width > screenFrame.maxX {
                x = sourceFrame.minX - panel.frame.width - gap
            }
            if x < screenFrame.minX {
                x = screenFrame.maxX - panel.frame.width - 8
            }

            let clampedY = min(max(y, screenFrame.minY), screenFrame.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: clampedY))
        } else {
            FloatingWindowManager.positionAtTopRight(panel, offset: 28)
        }
    }
}
```

- [ ] **Step 2: Create compact workbench view**

Create `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`:

```swift
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var viewModel: TranslationPanelViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            VStack(alignment: .leading, spacing: 10) {
                languageControls
                sourceSection
                translationSection
                actionBar
            }
            .padding(14)
        }
        .frame(width: 380, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var titleBar: some View {
        ZStack {
            TranslationPanelDragHandle()
            HStack {
                Text("翻译")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 38)
        .background(.regularMaterial)
    }

    private var languageControls: some View {
        HStack(spacing: 8) {
            languagePicker("源语言", selection: $viewModel.sourceLanguage, options: TranslationLanguage.sourceOptions)
            Button {
                viewModel.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.sourceLanguage == .auto || viewModel.isTranslating)
            .help("交换语言")
            languagePicker("目标语言", selection: $viewModel.targetLanguage, options: TranslationLanguage.targetOptions)
        }
    }

    private func languagePicker(
        _ title: String,
        selection: Binding<TranslationLanguage>,
        options: [TranslationLanguage]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("原文")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $viewModel.sourceText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
                .frame(height: 92)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("译文")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(translationText)
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.errorMessage == nil ? .primary : .red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .frame(height: 116)
        }
    }

    private var translationText: String {
        if viewModel.isTranslating {
            return "翻译中..."
        }
        if let errorMessage = viewModel.errorMessage {
            return errorMessage
        }
        return viewModel.translatedText
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.translate() }
            } label: {
                Text(viewModel.isTranslating ? "翻译中..." : "重新翻译")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isTranslating)

            Button {
                viewModel.copyTranslatedText()
            } label: {
                Text("复制译文")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.translatedText.isEmpty || viewModel.isTranslating)

            Spacer()
        }
    }
}
```

- [ ] **Step 3: Build after UI creation**

Run:

```bash
cd OneBoard && swift build
```

Expected: build succeeds. If SwiftUI reports style or import errors, fix only the new files.

## Task 4: Route Both Translation Entrances to the Workbench

**Files:**
- Modify: `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`

- [ ] **Step 1: Modify screenshot translation flow**

In `ScreenshotViewModel.performTranslation(on:)`, keep OCR, but replace `await translateText(text)` with:

```swift
TranslationPanelWindowManager.shared.show(
    sourceText: text,
    relativeTo: annotationWindow?.frame
)
```

Keep the empty-text branch:

```swift
guard !text.isEmpty else {
    translationResult = "没有可翻译的文字"
    AnnotationResultWindowManager.shared.show(
        title: "翻译",
        text: translationResult,
        relativeTo: annotationWindow?.frame
    )
    return
}
```

- [ ] **Step 2: Modify selected-text translation flow**

In `ScreenshotViewModel.translateSelectedText()`, replace the successful selected-text path with:

```swift
TranslationPanelWindowManager.shared.show(sourceText: selectedText)
```

Keep the no-selection branch using the simple result popup:

```swift
guard !selectedText.isEmpty else {
    translationResult = "没有检测到选中的文字"
    AnnotationResultWindowManager.shared.show(title: "翻译", text: translationResult)
    return
}
```

- [ ] **Step 3: Stop toolbar from opening the old translation popup**

In `AnnotationToolbarView`, find the translation button action that currently does:

```swift
await vm.performTranslation(on: rendered)
await AnnotationResultWindowManager.shared.show(title: "翻译", text: vm.translationResult)
```

Replace it with:

```swift
await vm.performTranslation(on: rendered)
```

- [ ] **Step 4: Build after routing changes**

Run:

```bash
cd OneBoard && swift build
```

Expected: build succeeds and there are no unused-result errors in the edited files.

## Task 5: Verify Behavior and Polish

**Files:**
- Modify only if verification reveals compile or interaction issues:
  - `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`
  - `OneBoard/Modules/Screenshot/Views/TranslationPanelWindowManager.swift`
  - `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
  - `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`

- [ ] **Step 1: Run focused tests**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: PASS.

- [ ] **Step 2: Run existing tests**

Run:

```bash
cd OneBoard && swift test
```

Expected: PASS for existing annotation and drag detector tests plus the new translation panel tests.

- [ ] **Step 3: Run required project build**

Run:

```bash
cd OneBoard && swift build
```

Expected: PASS. This satisfies the project rule that code changes must compile.

- [ ] **Step 4: Manual app check**

Run:

```bash
cd OneBoard && swift run
```

Manual checks:
- Use the global “翻译选中文字” hotkey on selected text. The compact translation workbench opens and automatically translates once.
- Change source/target languages in the panel. Confirm nothing translates until pressing “重新翻译”.
- Edit the original text. Press “重新翻译”. Confirm the edited text is sent.
- Press swap. Confirm source/target language and text fields swap when source language is not “自动检测”.
- Drag the panel by the top title bar. Confirm text areas and pickers do not drag the window.
- Press “复制译文”. Confirm the translated text is on the pasteboard.
- Confirm final UI does not show instructional copy such as “拖拽此区域移动”.

## Task 6: Update Development Log

**Files:**
- Modify: `开发日志/2026-06/2026-06-14.md`

- [ ] **Step 1: Add implementation summary**

Append:

```markdown
## 翻译浮框工作台

- 新增独立翻译浮框，支持原文编辑、译文查看、当前浮框内源语言/目标语言选择、语言交换、手动重新翻译和复制译文。
- 截图翻译和选中文字翻译统一使用新浮框，打开后按设置页默认语言自动首译一次。
- 浮框内语言选择仅对当前浮框生效，不写回默认设置。
- 修复翻译浮框无法拖拽的问题，改为仅顶部标题栏可拖拽。
- 验证：`swift test`、`swift build`。
```

- [ ] **Step 2: Final git status review**

Run:

```bash
git status --short
```

Expected: only intended implementation files, tests, plan/spec artifacts, preview artifacts if intentionally kept, and development log changes are listed. Do not stage or revert unrelated existing user changes.

## Plan Self-Review

- Spec coverage: The plan covers compact A layout, no instructional UI text, top-title drag only, editable source text, read-only/selectable translated text, manual retranslation, initial automatic translation, language selection local to the panel, swap, copy, two translation entrances, tests, build, and development log.
- Placeholder scan: No task uses TBD/TODO/fill-later language.
- Type consistency: `TranslationLanguage`, `TranslationPanelViewModel`, `TranslationPanelView`, and `TranslationPanelWindowManager` names are consistent across tests, implementation, and routing steps.
