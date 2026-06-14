# Clipboard Translation Staging Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish clipboard row/search behavior, rebuild the translation panel as a service-switching workbench, add Google web translation, enable Apple Translation on macOS 15+, and improve file staging preview clarity.

**Architecture:** Keep MVVM + Service Layer. Introduce a small `TranslationServiceType` model so settings, the translation panel, and the factory share one source of truth; keep Apple, Google, and DeepSeek as separate `TranslationServiceProtocol` implementations. UI changes stay scoped to the relevant SwiftUI views and use stable dimensions to avoid hover-driven layout jumps.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, Foundation URLSession, macOS 15+ Translation framework, XCTest, Swift Package Manager.

---

## File Structure

- Modify `OneBoard/Package.swift`: raise platform from macOS 14 to macOS 15.
- Modify `docs/需求文档/README.md` and `docs/技术规范/README.md`: sync platform and translation requirements.
- Modify `OneBoard/Core/Utilities/Constants.swift`: document translation service values and add staging thumbnail/window constants if helpful.
- Modify `OneBoard/App/AppSettings.swift`: default translation service remains Apple, support Google service value.
- Modify `OneBoard/App/OneBoardApp.swift`: settings picker shows Apple, Google, DeepSeek; API Key row only applies to DeepSeek.
- Create `OneBoard/Modules/Screenshot/Models/TranslationServiceType.swift`: service enum, display names, persisted raw values, API key requirement.
- Modify `OneBoard/Modules/Screenshot/Services/TranslationService.swift`: implement service factory by service type; add Google web client; replace Apple placeholder with macOS 15 Translation framework implementation.
- Modify `OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift`: current service state, service switching, clear source, status/error handling.
- Modify `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`: workbench layout with service segmented control, editable source, clean result, bottom status/actions.
- Modify `OneBoard/Modules/Clipboard/Views/ClipboardRowView.swift`: one-line truncation and stable action/time space.
- Modify `OneBoard/Modules/Clipboard/Views/ClipboardSearchBar.swift`: ensure click focus and input are not swallowed.
- Modify `OneBoard/Modules/Clipboard/Views/ClipboardListView.swift` and/or `ClipboardPopoverView.swift` only if focus or hit testing is currently blocked there.
- Modify `OneBoard/Core/Utilities/FileIconProvider.swift`: raise QuickLook thumbnail size and scale factor.
- Modify `OneBoard/Modules/FileStaging/Models/StagedFile.swift`: use the higher-resolution thumbnail request if thumbnail data is generated there.
- Modify `OneBoard/Modules/FileStaging/ViewModels/FileStagingViewModel.swift`: update shelf window width/height calculations.
- Modify `OneBoard/Modules/FileStaging/Views/FileStagingView.swift`: larger shelf UI, clear circular close/delete buttons.
- Modify `OneBoard/Tests/TranslationPanelViewModelTests.swift`: cover service switching, missing API key status, clearing, and stale request behavior with selected service.
- Add or modify tests only where the project already supports testable logic; visual-only SwiftUI layout is verified manually after build.

---

### Task 1: Platform and Translation Service Model

**Files:**
- Modify: `OneBoard/Package.swift`
- Modify: `docs/需求文档/README.md`
- Modify: `docs/技术规范/README.md`
- Modify: `OneBoard/Core/Utilities/Constants.swift`
- Modify: `OneBoard/App/AppSettings.swift`
- Create: `OneBoard/Modules/Screenshot/Models/TranslationServiceType.swift`

- [ ] **Step 1: Add the translation service type model**

Create `OneBoard/Modules/Screenshot/Models/TranslationServiceType.swift`:

```swift
import Foundation

/// 翻译服务选项。
enum TranslationServiceType: String, CaseIterable, Identifiable {
    case apple = "apple"
    case google = "google"
    case deepSeek = "deepseek"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        case .deepSeek:
            return "DeepSeek"
        }
    }

    var settingsDisplayName: String {
        switch self {
        case .apple:
            return "Apple Translation"
        case .google:
            return "Google 翻译"
        case .deepSeek:
            return "DeepSeek AI 翻译"
        }
    }

    var requiresAPIKey: Bool {
        self == .deepSeek
    }

    static func current(defaults: UserDefaults = .standard) -> TranslationServiceType {
        let rawValue = defaults.string(forKey: Constants.UserDefaultsKeys.translationServiceType)
        return TranslationServiceType(rawValue: rawValue ?? "") ?? .apple
    }
}
```

- [ ] **Step 2: Raise the package platform**

In `OneBoard/Package.swift`, change:

```swift
platforms: [
    .macOS(.v14)
],
```

to:

```swift
platforms: [
    .macOS(.v15)
],
```

- [ ] **Step 3: Update default service comments and app settings**

In `OneBoard/Core/Utilities/Constants.swift`, update the translation service comment:

```swift
static let translationServiceType = "translation_service_type"  // "apple" | "google" | "deepseek"
```

In `OneBoard/App/AppSettings.swift`, update the translation service comment:

```swift
/// 翻译服务类型: "apple" | "google" | "deepseek"
@AppStorage(Constants.UserDefaultsKeys.translationServiceType)
static var translationServiceType: String = TranslationServiceType.apple.rawValue
```

- [ ] **Step 4: Update documentation platform references**

Update `docs/需求文档/README.md`:

```markdown
- **平台**：macOS 15.0+
```

Update `docs/技术规范/README.md` platform rows:

```markdown
| UI 框架 | SwiftUI + AppKit | macOS 15.0+ |
| 翻译 | Apple Translation / Google Web / DeepSeek | macOS 15.0+ |
```

- [ ] **Step 5: Build check**

Run:

```bash
cd OneBoard && swift build
```

Expected: build may still fail if `AppSettings.swift` cannot see the new enum due to target source inclusion mistakes. Fix path/name issues before moving on.

---

### Task 2: Translation Service Implementations

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Services/TranslationService.swift`
- Test: `OneBoard/Tests/TranslationPanelViewModelTests.swift`

- [ ] **Step 1: Add test coverage for service selection at the ViewModel layer**

Add a recording service provider to `TranslationPanelViewModelTests.swift` after the existing helpers:

```swift
private final class RecordingTranslationServiceProvider {
    private(set) var requestedTypes: [TranslationServiceType] = []
    let services: [TranslationServiceType: RecordingTranslationService]

    init() {
        services = [
            .apple: RecordingTranslationService(result: "apple result"),
            .google: RecordingTranslationService(result: "google result"),
            .deepSeek: RecordingTranslationService(result: "deepseek result"),
        ]
    }

    func service(for type: TranslationServiceType) -> TranslationServiceProtocol {
        requestedTypes.append(type)
        return services[type]!
    }
}
```

Then add a test:

```swift
func testServiceSwitchRetranslatesWithSelectedService() async {
    let defaults = makeDefaults()
    defaults.set(TranslationServiceType.apple.rawValue, forKey: Constants.UserDefaultsKeys.translationServiceType)
    let provider = RecordingTranslationServiceProvider()
    let viewModel = TranslationPanelViewModel(
        sourceText: "hello",
        translationServiceType: .apple,
        translationServiceProvider: provider.service(for:),
        defaults: defaults
    )

    await viewModel.selectService(.google)

    XCTAssertEqual(viewModel.translationServiceType, .google)
    XCTAssertEqual(viewModel.translatedText, "google result")
    XCTAssertEqual(provider.requestedTypes, [.google])
    XCTAssertEqual(defaults.string(forKey: Constants.UserDefaultsKeys.translationServiceType), "apple")
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests/testServiceSwitchRetranslatesWithSelectedService
```

Expected: FAIL because `TranslationServiceType`, `translationServiceType`, and the provider initializer do not exist yet.

- [ ] **Step 3: Implement service factory and clients**

In `TranslationService.swift`, keep `TranslationServiceProtocol` and replace service classes/factory with:

```swift
import Foundation
import AppKit
import Translation

protocol TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String
}

final class AppleTranslationService: TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        let source = sourceLanguage.flatMap(Locale.Language.init(identifier:))
        let target = Locale.Language(identifier: targetLanguage)
        let session = TranslationSession(
            configuration: .init(source: source, target: target)
        )
        let response = try await session.translate(text)
        return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class GoogleTranslationService: TranslationServiceProtocol {
    private let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!

    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sourceLanguage ?? "auto"),
            URLQueryItem(name: "tl", value: googleLanguageCode(targetLanguage)),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else {
            throw TranslationServiceError.translationFailed("Google 翻译请求无效")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 OneBoard", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.translationFailed("Google 翻译暂不可用，请稍后重试")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [Any],
            let segments = json.first as? [Any]
        else {
            throw TranslationServiceError.translationFailed("Google 翻译返回格式异常")
        }

        let translated = segments.compactMap { segment -> String? in
            guard let values = segment as? [Any] else { return nil }
            return values.first as? String
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else {
            throw TranslationServiceError.translationFailed("Google 翻译返回了空结果")
        }
        return translated
    }

    private func googleLanguageCode(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return code
        }
    }
}

final class DeepSeekTranslationService: TranslationServiceProtocol {
    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        try await DeepSeekTranslationClient().translate(
            text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }
}
```

Keep the existing `DeepSeekTranslationClient`, request/response models, and `TranslationServiceError`, but update `missingAPIKey` text to:

```swift
return "请先在设置中填写 DeepSeek API Key"
```

Update `TranslationServiceFactory`:

```swift
enum TranslationServiceFactory {
    static func create(type: TranslationServiceType = .current()) -> TranslationServiceProtocol {
        switch type {
        case .apple:
            return AppleTranslationService()
        case .google:
            return GoogleTranslationService()
        case .deepSeek:
            return DeepSeekTranslationService()
        }
    }
}
```

- [ ] **Step 4: Build to catch Translation framework API details**

Run:

```bash
cd OneBoard && swift build
```

Expected: PASS. If the exact `TranslationSession` initializer differs on the installed SDK, adjust only `AppleTranslationService` to the SDK compiler error while preserving the `TranslationServiceProtocol` contract.

---

### Task 3: Translation Panel ViewModel and Workbench UI

**Files:**
- Modify: `OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift`
- Modify: `OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift`
- Modify: `OneBoard/App/OneBoardApp.swift`
- Test: `OneBoard/Tests/TranslationPanelViewModelTests.swift`

- [ ] **Step 1: Extend ViewModel initialization for service injection**

Modify `TranslationPanelViewModel` properties and initializer to include:

```swift
@Published var translationServiceType: TranslationServiceType

private let translationServiceProvider: (TranslationServiceType) -> TranslationServiceProtocol
private var translationService: TranslationServiceProtocol {
    translationServiceProvider(translationServiceType)
}
```

Use this initializer shape:

```swift
init(
    sourceText: String,
    translationServiceType: TranslationServiceType = .current(),
    translationServiceProvider: @escaping (TranslationServiceType) -> TranslationServiceProtocol = TranslationServiceFactory.create(type:),
    defaults: UserDefaults = .standard
) {
    self.sourceText = sourceText
    self.translationServiceType = translationServiceType
    self.translationServiceProvider = translationServiceProvider
    self.defaults = defaults
    self.sourceLanguage = TranslationLanguage.sourceDefault(defaults: defaults)
    self.targetLanguage = TranslationLanguage.targetDefault(defaults: defaults)
}
```

- [ ] **Step 2: Add clear and service selection methods**

Add:

```swift
func clearSourceText() {
    translationRequestID += 1
    sourceText = ""
    translatedText = ""
    errorMessage = nil
    isTranslating = false
}

func selectService(_ serviceType: TranslationServiceType) async {
    guard translationServiceType != serviceType else { return }
    translationRequestID += 1
    translationServiceType = serviceType
    translatedText = ""
    errorMessage = nil
    await translate()
}
```

Keep `translate()` using `translationService.translate(...)`, now resolved from the current service type.

- [ ] **Step 3: Add focused ViewModel tests**

Add tests:

```swift
func testClearSourceTextCancelsVisibleState() {
    let viewModel = TranslationPanelViewModel(
        sourceText: "hello",
        translationServiceProvider: { _ in RecordingTranslationService(result: "ignored") },
        defaults: makeDefaults()
    )
    viewModel.translatedText = "你好"
    viewModel.errorMessage = "old"
    viewModel.isTranslating = true

    viewModel.clearSourceText()

    XCTAssertEqual(viewModel.sourceText, "")
    XCTAssertEqual(viewModel.translatedText, "")
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertFalse(viewModel.isTranslating)
}

func testDeepSeekMissingKeyErrorIsDisplayedOutsideTranslationText() async {
    let service = RecordingTranslationService(error: TranslationServiceError.missingAPIKey)
    let viewModel = TranslationPanelViewModel(
        sourceText: "hello",
        translationServiceType: .deepSeek,
        translationServiceProvider: { _ in service },
        defaults: makeDefaults()
    )

    await viewModel.translate()

    XCTAssertEqual(viewModel.translatedText, "")
    XCTAssertEqual(viewModel.errorMessage, "请先在设置中填写 DeepSeek API Key")
}
```

- [ ] **Step 4: Run ViewModel tests**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
```

Expected: PASS after implementation.

- [ ] **Step 5: Rebuild `TranslationPanelView` as the workbench**

Replace the current body structure with:

```swift
var body: some View {
    VStack(spacing: 0) {
        titleBar
        VStack(alignment: .leading, spacing: 12) {
            servicePicker
            languageControls
            sourceSection
            translationSection
            actionBar
        }
        .padding(14)
    }
    .frame(width: 520, height: 560)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
    )
}
```

Add a segmented service picker:

```swift
private var servicePicker: some View {
    Picker("翻译服务", selection: $viewModel.translationServiceType) {
        ForEach(TranslationServiceType.allCases) { service in
            Text(service.displayName).tag(service)
        }
    }
    .pickerStyle(.segmented)
    .onChange(of: viewModel.translationServiceType) { _, newValue in
        Task { await viewModel.selectService(newValue) }
    }
}
```

Make the source area editable with a clear button:

```swift
private var sourceSection: some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text("原文").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.clearSourceText()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.sourceText.isEmpty)
            .help("清空")
        }
        TextEditor(text: $viewModel.sourceText)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.12), lineWidth: 1))
            .frame(height: 138)
    }
}
```

Show errors only in the bottom status/action area:

```swift
private var actionBar: some View {
    HStack(spacing: 10) {
        Text(statusText)
            .font(.system(size: 12))
            .foregroundStyle(viewModel.errorMessage == nil ? .secondary : .red)
            .lineLimit(2)
        Spacer()
        Button("重新翻译") {
            Task { await onTranslateAsync() }
        }
        .disabled(viewModel.isTranslating || viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("复制译文") {
            viewModel.copyTranslatedText()
        }
        .disabled(viewModel.translatedText.isEmpty)
    }
}

private var statusText: String {
    if viewModel.isTranslating { return "正在翻译..." }
    if let error = viewModel.errorMessage { return error }
    if viewModel.translationServiceType == .deepSeek { return "DeepSeek 使用设置中的 API Key" }
    if viewModel.translationServiceType == .google { return "Google 使用网页版接口" }
    return "Apple 使用系统 Translation"
}

private func onTranslateAsync() async {
    onTranslate()
}
```

If the existing `onTranslate` closure is synchronous, keep button action as `Task { await viewModel.translate() }` and remove `onTranslateAsync()`.

- [ ] **Step 6: Update settings UI**

In `SettingsView`, replace hard-coded translation picker values with:

```swift
Picker("翻译服务", selection: $translationServiceType) {
    ForEach(TranslationServiceType.allCases) { service in
        Text(service.settingsDisplayName).tag(service.rawValue)
    }
}
```

Only show the translation API key row when:

```swift
TranslationServiceType(rawValue: translationServiceType)?.requiresAPIKey == true
```

- [ ] **Step 7: Build and run tests**

Run:

```bash
cd OneBoard && swift test --filter TranslationPanelViewModelTests
cd OneBoard && swift build
```

Expected: PASS.

---

### Task 4: Clipboard Search Focus and Stable Row Layout

**Files:**
- Modify: `OneBoard/Modules/Clipboard/Views/ClipboardRowView.swift`
- Modify: `OneBoard/Modules/Clipboard/Views/ClipboardSearchBar.swift`
- Modify if needed: `OneBoard/Modules/Clipboard/Views/ClipboardListView.swift`
- Modify if needed: `OneBoard/Modules/Clipboard/Views/ClipboardPopoverView.swift`

- [ ] **Step 1: Stabilize action/time layout in row**

In `ClipboardRowView`, replace the hover-only action insertion:

```swift
if isHovered {
    actionButtons
}
```

with a stable-width container:

```swift
actionButtons
    .opacity(isHovered ? 1 : 0)
    .allowsHitTesting(isHovered)
    .frame(width: 42, alignment: .trailing)
```

Keep the time label fixed width.

- [ ] **Step 2: Force single-line truncation**

In both pinned and unpinned preview `Text(entry.previewText)`, use:

```swift
.lineLimit(1)
.truncationMode(.tail)
```

For the `VStack` container, add:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
.clipped()
```

For the pinned `HStack`, add:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
```

- [ ] **Step 3: Ensure search field accepts clicks and typing**

In `ClipboardSearchBar`, ensure the text field has a focusable text input shape:

```swift
TextField("搜索剪贴板历史", text: $searchText)
    .textFieldStyle(.plain)
    .focusable(true)
```

If the search bar root has `.onTapGesture`, make it focus the field instead of doing nothing. Use:

```swift
@FocusState private var isSearchFocused: Bool
```

and:

```swift
.focused($isSearchFocused)
.onTapGesture {
    isSearchFocused = true
}
```

- [ ] **Step 4: Remove hit-test blockers around the search bar if present**

Inspect `ClipboardListView` and `ClipboardPopoverView` for a parent `.onTapGesture`, `.contentShape`, or overlay that covers the search bar. If present, scope it to the list rows instead of the whole popover.

- [ ] **Step 5: Manual verification**

Run:

```bash
cd OneBoard && swift build
```

Expected: PASS.

Manual checks:
- Open clipboard popover.
- Click the search field; typing goes into the field.
- Search filters results.
- Hover a long text row; row stays single-line with ellipsis and no height jump.

---

### Task 5: File Staging Higher-Quality Preview and Softer Delete Button

**Files:**
- Modify: `OneBoard/Core/Utilities/FileIconProvider.swift`
- Modify: `OneBoard/Modules/FileStaging/Models/StagedFile.swift`
- Modify: `OneBoard/Modules/FileStaging/ViewModels/FileStagingViewModel.swift`
- Modify: `OneBoard/Modules/FileStaging/Views/FileStagingView.swift`

- [ ] **Step 1: Increase thumbnail generation quality**

In `FileIconProvider.thumbnail`, change defaults:

```swift
static func thumbnail(for url: URL, size: NSSize = NSSize(width: 160, height: 160)) -> NSImage? {
    let options: [CFString: Any] = [
        kQLThumbnailOptionIconModeKey: false,
        kQLThumbnailOptionScaleFactorKey: NSScreen.main?.backingScaleFactor ?? 2.0,
    ]
```

- [ ] **Step 2: Ensure staged files store larger thumbnails**

In `StagedFile.swift`, find the thumbnail generation call and use:

```swift
FileIconProvider.thumbnail(for: url, size: NSSize(width: 160, height: 160))
```

Keep PNG encoding as-is unless the file already uses another format.

- [ ] **Step 3: Increase shelf window dimensions**

In `FileStagingViewModel.updateFloatingWindow`, change:

```swift
let width: CGFloat = 348
let rows = max(1, Int(ceil(Double(max(stagedFiles.count, 1)) / 3.0)))
let height = stagedFiles.isEmpty ? CGFloat(190) : min(CGFloat(rows) * 126 + 64, 430)
```

- [ ] **Step 4: Update staging view layout constants**

In `FileStagingView`, adjust:

```swift
.frame(width: 348)
```

Use adaptive grid:

```swift
GridItem(.adaptive(minimum: 92), spacing: 14)
```

Use tile size:

```swift
.frame(width: 96, height: 116)
```

Use preview size:

```swift
.frame(width: 72, height: 78)
.padding(10)
```

- [ ] **Step 5: Replace close button with a crisp circular control**

Change `circleButton` label body to:

```swift
Image(systemName: icon)
    .font(.system(size: 13, weight: .semibold))
    .foregroundColor(.black.opacity(0.58))
    .frame(width: 30, height: 30)
    .background(Circle().fill(Color.white.opacity(0.62)))
    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
```

- [ ] **Step 6: Replace file delete button with softer hover-aware circle**

Add a hover state to each tile by extracting a small view if needed. Minimal approach:

```swift
private struct StagedFileDeleteButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isHovered ? .white : OneBoardColors.destructive.opacity(0.78))
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(isHovered ? OneBoardColors.destructive : Color.white.opacity(0.88))
                )
                .overlay(
                    Circle().stroke(OneBoardColors.destructive.opacity(isHovered ? 0 : 0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help("移除")
    }
}
```

Use it in `stagedFileTile`:

```swift
StagedFileDeleteButton {
    Task { await viewModel.removeFile(file) }
}
.offset(x: 7, y: -7)
```

- [ ] **Step 7: Build and manual verification**

Run:

```bash
cd OneBoard && swift build
```

Expected: PASS.

Manual checks:
- Drag a file into the shelf.
- Thumbnail is visibly sharper and larger.
- The file delete button feels integrated: soft at rest, red on hover.
- Window close button is a clean circle.
- File name remains one line with ellipsis.

---

### Task 6: Final Verification and Development Log

**Files:**
- Modify: `开发日志/2026-06/2026-06-14.md`
- Modify if needed: `docs/开发步骤/README.md`

- [ ] **Step 1: Run the full verification suite**

Run:

```bash
cd OneBoard && swift test
cd OneBoard && swift build
```

Expected: both PASS.

- [ ] **Step 2: Update the development log**

Append to `开发日志/2026-06/2026-06-14.md`:

```markdown
## 剪贴板、翻译、暂存区体验优化

- 修复剪贴板长文本悬浮后换行的问题，改为单行省略。
- 修复剪贴板搜索框点击后无法输入的问题。
- 翻译面板升级为工作台，可切换 Apple、Google、DeepSeek。
- Apple Translation 接入 macOS 15+ 系统 Translation 框架。
- 新增 Google 网页翻译接口。
- 暂存区窗口、缩略图和圆形按钮视觉优化。

验证：
- `swift test`
- `swift build`
```

- [ ] **Step 3: Check development step status**

Open `docs/开发步骤/README.md`. If it has explicit checklist items for translation or file staging polish, mark only the completed items. If it only tracks phase-level completion, do not mark Phase 2 or Phase 3 complete unless all phase requirements are actually finished.

- [ ] **Step 4: Review diff**

Run:

```bash
git diff --stat
git diff -- OneBoard/Modules/Screenshot/Services/TranslationService.swift
git diff -- OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift
git diff -- OneBoard/Modules/FileStaging/Views/FileStagingView.swift
```

Expected: changes match this plan; no unrelated user changes are reverted.

- [ ] **Step 5: Commit implementation**

Stage only files changed for this plan:

```bash
git add OneBoard/Package.swift docs/需求文档/README.md docs/技术规范/README.md OneBoard/Core/Utilities/Constants.swift OneBoard/App/AppSettings.swift OneBoard/App/OneBoardApp.swift OneBoard/Modules/Screenshot/Models/TranslationServiceType.swift OneBoard/Modules/Screenshot/Services/TranslationService.swift OneBoard/Modules/Screenshot/ViewModels/TranslationPanelViewModel.swift OneBoard/Modules/Screenshot/Views/TranslationPanelView.swift OneBoard/Modules/Clipboard/Views/ClipboardRowView.swift OneBoard/Modules/Clipboard/Views/ClipboardSearchBar.swift OneBoard/Core/Utilities/FileIconProvider.swift OneBoard/Modules/FileStaging/Models/StagedFile.swift OneBoard/Modules/FileStaging/ViewModels/FileStagingViewModel.swift OneBoard/Modules/FileStaging/Views/FileStagingView.swift OneBoard/Tests/TranslationPanelViewModelTests.swift 开发日志/2026-06/2026-06-14.md docs/开发步骤/README.md
git commit -m "Polish clipboard translation and staging UI"
```

If `docs/开发步骤/README.md` is unchanged, omit it from `git add`.

---

## Self-Review

- Spec coverage: clipboard wrapping/search is Task 4; translation workbench, service switching, Google, Apple, and DeepSeek handling are Tasks 1-3; staging preview and buttons are Task 5; docs/log/build verification are Tasks 1 and 6.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: `TranslationServiceType`, `TranslationServiceFactory.create(type:)`, and `TranslationPanelViewModel.translationServiceType` are used consistently across tasks.
