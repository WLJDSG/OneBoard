import AppKit
@testable import OneBoardKit
import XCTest

@MainActor
final class TranslationPanelViewModelTests: XCTestCase {
    func testAutoSourceAllowedButNotTarget() {
        XCTAssertTrue(TranslationLanguage.sourceOptions.contains(.auto))
        XCTAssertFalse(TranslationLanguage.targetOptions.contains(.auto))
    }

    func testDisplayNames() {
        XCTAssertEqual(TranslationLanguage.auto.displayName, "自动检测")
        XCTAssertEqual(TranslationLanguage.english.displayName, "英文")
        XCTAssertEqual(TranslationLanguage.simplifiedChinese.displayName, "中文（简体）")
        XCTAssertEqual(TranslationLanguage.traditionalChinese.displayName, "中文（繁体）")
        XCTAssertEqual(TranslationLanguage.japanese.displayName, "日文")
        XCTAssertEqual(TranslationLanguage.korean.displayName, "韩文")
        XCTAssertEqual(TranslationLanguage.french.displayName, "法文")
        XCTAssertEqual(TranslationLanguage.german.displayName, "德文")
    }

    func testAutoSourceLanguageInferenceForCommonText() {
        XCTAssertEqual(TranslationLanguage.inferredSource(for: "18个测试通过"), .simplifiedChinese)
        XCTAssertEqual(TranslationLanguage.inferredSource(for: "hello world"), .english)
        XCTAssertEqual(TranslationLanguage.inferredSource(for: "こんにちは"), .japanese)
        XCTAssertEqual(TranslationLanguage.inferredSource(for: "테스트"), .korean)
    }

    func testInitialTranslateUsesDefaultsWithoutSavingTemporaryChanges() async {
        let defaults = makeDefaults()
        defaults.set(TranslationLanguage.simplifiedChinese.rawValue, forKey: Constants.UserDefaultsKeys.translationSourceLanguage)
        defaults.set(TranslationLanguage.german.rawValue, forKey: Constants.UserDefaultsKeys.translationTargetLanguage)
        let service = RecordingTranslationService(result: "Hallo")
        let viewModel = TranslationPanelViewModel(sourceText: "  你好  ", translationService: service, defaults: defaults)

        viewModel.sourceLanguage = .japanese
        viewModel.targetLanguage = .french
        await viewModel.translate()

        XCTAssertEqual(service.requests, [
            .init(text: "你好", sourceLanguage: "ja", targetLanguage: "fr")
        ])
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaultsKeys.translationSourceLanguage), "zh-Hans")
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaultsKeys.translationTargetLanguage), "de")
        XCTAssertEqual(viewModel.translatedText, "Hallo")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testManualRetranslateUsesEditedSourceAndCurrentPanelLanguages() async {
        let defaults = makeDefaults()
        let service = RecordingTranslationService(result: "Translated")
        let viewModel = TranslationPanelViewModel(sourceText: "original", translationService: service, defaults: defaults)

        viewModel.sourceText = "  edited text  "
        viewModel.sourceLanguage = .auto
        viewModel.targetLanguage = .traditionalChinese
        await viewModel.translate()

        XCTAssertEqual(service.requests, [
            .init(text: "edited text", sourceLanguage: nil, targetLanguage: "zh-Hant")
        ])
        XCTAssertEqual(viewModel.translatedText, "Translated")
    }

    func testServiceSwitchRetranslatesWithSelectedServiceWithoutSavingDefault() async {
        let defaults = makeDefaults()
        defaults.set(TranslationServiceType.apple.rawValue, forKey: Constants.UserDefaultsKeys.translationServiceType)
        let appleService = RecordingTranslationService(result: "Apple result")
        let googleService = RecordingTranslationService(result: "Google result")
        let deepSeekService = RecordingTranslationService(result: "DeepSeek result")
        let viewModel = TranslationPanelViewModel(
            sourceText: " hello ",
            translationServiceProvider: { serviceType in
                switch serviceType {
                case .apple:
                    return appleService
                case .google:
                    return googleService
                case .deepSeek:
                    return deepSeekService
                }
            },
            defaults: defaults
        )
        viewModel.sourceLanguage = .english
        viewModel.targetLanguage = .simplifiedChinese
        viewModel.translatedText = "old"
        viewModel.errorMessage = "old error"

        await viewModel.selectService(.google)

        XCTAssertEqual(viewModel.translationServiceType, .google)
        XCTAssertEqual(viewModel.translatedText, "Google result")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(appleService.requests.isEmpty)
        XCTAssertEqual(googleService.requests, [
            .init(text: "hello", sourceLanguage: "en", targetLanguage: "zh-Hans")
        ])
        XCTAssertTrue(deepSeekService.requests.isEmpty)
        XCTAssertEqual(defaults.string(forKey: Constants.UserDefaultsKeys.translationServiceType), "apple")
    }

    func testClearSourceTextClearsStateAndInvalidatesStaleRequest() async {
        let service = DelayedTranslationService()
        let viewModel = TranslationPanelViewModel(sourceText: "hello", translationService: service, defaults: makeDefaults())
        viewModel.sourceLanguage = .english
        viewModel.targetLanguage = .french
        viewModel.translatedText = "old"
        viewModel.errorMessage = "old error"

        let task = Task { await viewModel.translate() }
        await waitForPendingRequests(1, in: service)

        viewModel.clearSourceText()

        XCTAssertEqual(viewModel.sourceText, "")
        XCTAssertEqual(viewModel.translatedText, "")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isTranslating)

        service.completeRequest(at: 0, with: "bonjour")
        await task.value

        XCTAssertEqual(viewModel.sourceText, "")
        XCTAssertEqual(viewModel.translatedText, "")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testDeepSeekMissingAPIKeyKeepsErrorMessageAndEmptyTranslation() async {
        let defaults = makeDefaults()
        defaults.set(TranslationServiceType.deepSeek.rawValue, forKey: Constants.UserDefaultsKeys.translationServiceType)
        let viewModel = TranslationPanelViewModel(sourceText: "hello", defaults: defaults)
        viewModel.translatedText = "old"

        await viewModel.translate()

        XCTAssertEqual(viewModel.translationServiceType, .deepSeek)
        XCTAssertEqual(viewModel.translatedText, "")
        XCTAssertEqual(viewModel.errorMessage, "请先选择已添加的 API Key")
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testSwapLanguagesMovesTranslatedTextIntoSourceWhenSourceIsNotAuto() {
        let viewModel = TranslationPanelViewModel(
            sourceText: "Hello",
            translationService: RecordingTranslationService(result: "你好"),
            defaults: makeDefaults()
        )
        viewModel.sourceLanguage = .english
        viewModel.targetLanguage = .simplifiedChinese
        viewModel.translatedText = "你好"
        viewModel.errorMessage = "old error"

        viewModel.swapLanguages()

        XCTAssertEqual(viewModel.sourceLanguage, .simplifiedChinese)
        XCTAssertEqual(viewModel.targetLanguage, .english)
        XCTAssertEqual(viewModel.sourceText, "你好")
        XCTAssertEqual(viewModel.translatedText, "Hello")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailureKeepsSourceTextAndShowsError() async {
        let service = RecordingTranslationService(error: TranslationTestError.expected)
        let viewModel = TranslationPanelViewModel(sourceText: "Keep me", translationService: service, defaults: makeDefaults())
        viewModel.translatedText = "old translation"

        await viewModel.translate()

        XCTAssertEqual(viewModel.sourceText, "Keep me")
        XCTAssertEqual(viewModel.translatedText, "")
        XCTAssertEqual(viewModel.errorMessage, "预期失败")
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testStaleTranslationDoesNotOverwriteNewerResult() async {
        let service = DelayedTranslationService()
        let viewModel = TranslationPanelViewModel(sourceText: "first", translationService: service, defaults: makeDefaults())
        viewModel.sourceLanguage = .english
        viewModel.targetLanguage = .french

        let firstTask = Task { await viewModel.translate() }
        await waitForPendingRequests(1, in: service)

        viewModel.sourceText = "second"
        viewModel.targetLanguage = .german
        let secondTask = Task { await viewModel.translate() }
        await waitForPendingRequests(2, in: service)

        service.completeRequest(at: 1, with: "new result")
        await secondTask.value
        XCTAssertEqual(viewModel.translatedText, "new result")
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertFalse(viewModel.isTranslating)

        service.completeRequest(at: 0, with: "old result")
        await firstTask.value
        XCTAssertEqual(viewModel.translatedText, "new result")
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertEqual(service.requests, [
            .init(text: "first", sourceLanguage: "en", targetLanguage: "fr"),
            .init(text: "second", sourceLanguage: "en", targetLanguage: "de")
        ])
    }

    func testLanguageChangeDuringInFlightTranslationDropsStaleResult() async {
        let service = DelayedTranslationService()
        let viewModel = TranslationPanelViewModel(sourceText: "hello", translationService: service, defaults: makeDefaults())
        viewModel.sourceLanguage = .english
        viewModel.targetLanguage = .french

        let task = Task { await viewModel.translate() }
        await waitForPendingRequests(1, in: service)

        viewModel.targetLanguage = .german
        service.completeRequest(at: 0, with: "bonjour")
        await task.value

        XCTAssertEqual(viewModel.translatedText, "")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertEqual(service.requests, [
            .init(text: "hello", sourceLanguage: "en", targetLanguage: "fr")
        ])
    }

    func testSwapLanguagesDoesNothingWhenTranslationIsEmpty() {
        let viewModel = TranslationPanelViewModel(
            sourceText: "Hello",
            translationService: RecordingTranslationService(),
            defaults: makeDefaults()
        )
        viewModel.sourceLanguage = .english
        viewModel.targetLanguage = .simplifiedChinese
        viewModel.translatedText = ""

        viewModel.swapLanguages()

        XCTAssertEqual(viewModel.sourceLanguage, .english)
        XCTAssertEqual(viewModel.targetLanguage, .simplifiedChinese)
        XCTAssertEqual(viewModel.sourceText, "Hello")
        XCTAssertEqual(viewModel.translatedText, "")
    }

    func testCopyTranslatedTextCopiesNonEmptyTextToPasteboard() {
        var copiedText: String?
        let viewModel = TranslationPanelViewModel(
            sourceText: "Bonjour",
            translationService: RecordingTranslationService(),
            pasteboardWriter: { copiedText = $0 },
            defaults: makeDefaults()
        )

        viewModel.translatedText = "Hello"

        viewModel.copyTranslatedText()

        XCTAssertEqual(copiedText, "Hello")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TranslationPanelViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitForPendingRequests(
        _ count: Int,
        in service: DelayedTranslationService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if service.pendingRequestCount >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected \(count) pending translation requests", file: file, line: line)
    }
}

private struct TranslationRequest: Equatable {
    let text: String
    let sourceLanguage: String?
    let targetLanguage: String
}

private final class RecordingTranslationService: TranslationServiceProtocol {
    private(set) var requests: [TranslationRequest] = []
    private let result: String
    private let error: Error?

    init(result: String = "", error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        requests.append(.init(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
        if let error {
            throw error
        }
        return result
    }
}

private enum TranslationTestError: LocalizedError {
    case expected

    var errorDescription: String? {
        "预期失败"
    }
}

private final class DelayedTranslationService: TranslationServiceProtocol {
    private(set) var requests: [TranslationRequest] = []
    private var pendingRequests: [CheckedContinuation<String, Error>?] = []

    var pendingRequestCount: Int {
        pendingRequests.compactMap { $0 }.count
    }

    func translate(_ text: String, from sourceLanguage: String?, to targetLanguage: String) async throws -> String {
        requests.append(.init(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.append(continuation)
        }
    }

    func completeRequest(at index: Int, with result: String) {
        let continuation = pendingRequests[index]
        pendingRequests[index] = nil
        continuation?.resume(returning: result)
    }
}
