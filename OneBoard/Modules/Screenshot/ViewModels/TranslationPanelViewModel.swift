import AppKit
import Combine
import Foundation
import Translation

@MainActor
final class TranslationPanelViewModel: ObservableObject {
    @Published var selectedProviderID: String
    @Published var sourceText: String
    @Published var translatedText: String
    @Published var sourceLanguage: TranslationLanguage
    @Published var targetLanguage: TranslationLanguage
    @Published var translationServiceType: TranslationServiceType
    @Published var isTranslating: Bool
    @Published var errorMessage: String?
    @Published var appleTranslationConfiguration: TranslationSession.Configuration?

    private let translationServiceProvider: (TranslationServiceType) -> TranslationServiceProtocol
    private let usesInjectedTranslationService: Bool
    private let pasteboardWriter: @MainActor (String) -> Void
    private var translationRequestID = 0
    private var pendingAppleRequest: TranslationRequestSnapshot?

    init(
        sourceText: String,
        translationServiceType: TranslationServiceType? = nil,
        translationServiceProvider: @escaping (TranslationServiceType) -> TranslationServiceProtocol = TranslationServiceFactory.create(type:),
        usesInjectedTranslationService: Bool = false,
        pasteboardWriter: @escaping @MainActor (String) -> Void = TranslationPanelViewModel.writeStringToGeneralPasteboard,
        defaults: UserDefaults = .standard
    ) {
        self.selectedProviderID = defaults.string(forKey: ConfiguredAITranslationService.selectionKey) ?? ""
        self.sourceText = sourceText
        translatedText = ""
        sourceLanguage = TranslationLanguage.sourceDefault(defaults: defaults)
        targetLanguage = TranslationLanguage.targetDefault(defaults: defaults)
        self.translationServiceType = translationServiceType ?? .current(defaults: defaults)
        isTranslating = false
        errorMessage = nil
        self.translationServiceProvider = translationServiceProvider
        self.usesInjectedTranslationService = usesInjectedTranslationService
        self.pasteboardWriter = pasteboardWriter
    }

    convenience init(
        sourceText: String,
        translationService: TranslationServiceProtocol,
        pasteboardWriter: @escaping @MainActor (String) -> Void = TranslationPanelViewModel.writeStringToGeneralPasteboard,
        defaults: UserDefaults = .standard
    ) {
        self.init(
            sourceText: sourceText,
            translationServiceType: .current(defaults: defaults),
            translationServiceProvider: { _ in translationService },
            usesInjectedTranslationService: true,
            pasteboardWriter: pasteboardWriter,
            defaults: defaults
        )
    }

    func translate() async {
        translationRequestID += 1
        let requestID = translationRequestID
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedSourceText = trimmedText
        let requestedSourceLanguage = sourceLanguage
        let requestedTargetLanguage = targetLanguage
        let requestedServiceType = translationServiceType
        let translationService: TranslationServiceProtocol = requestedServiceType == .deepSeek && !usesInjectedTranslationService
            ? ConfiguredAITranslationService(providerID: UUID(uuidString: selectedProviderID))
            : translationServiceProvider(requestedServiceType)
        let shouldInferAppleSource = requestedServiceType == .apple && !usesInjectedTranslationService
        let inferredSourceLanguage = shouldInferAppleSource ? TranslationLanguage.inferredSource(for: trimmedText) : nil
        let effectiveSourceLanguage = sourceLanguage == .auto ? inferredSourceLanguage : sourceLanguage
        let sourceCode = effectiveSourceLanguage?.rawValue
        let targetCode = targetLanguage.rawValue

        guard !trimmedText.isEmpty else {
            translatedText = ""
            errorMessage = "没有可翻译的文字"
            isTranslating = false
            return
        }

        isTranslating = true
        errorMessage = nil

        if requestedServiceType == .apple, !usesInjectedTranslationService {
            pendingAppleRequest = TranslationRequestSnapshot(
                requestID: requestID,
                text: requestedSourceText,
                sourceLanguage: requestedSourceLanguage,
                targetLanguage: requestedTargetLanguage,
                serviceType: requestedServiceType
            )
            var configuration = appleTranslationConfiguration ?? TranslationSession.Configuration()
            configuration.source = sourceCode.map { Locale.Language(identifier: $0) }
            configuration.target = Locale.Language(identifier: targetCode)
            configuration.invalidate()
            appleTranslationConfiguration = configuration
            return
        }

        do {
            let result = try await translationService.translate(trimmedText, from: sourceCode, to: targetCode)
            guard !Task.isCancelled, requestID == translationRequestID else { return }
            guard requestStillMatches(
                sourceText: requestedSourceText,
                sourceLanguage: requestedSourceLanguage,
                targetLanguage: requestedTargetLanguage,
                serviceType: requestedServiceType
            ) else {
                isTranslating = false
                return
            }
            translatedText = result
            errorMessage = nil
        } catch is CancellationError {
            guard requestID == translationRequestID else { return }
            isTranslating = false
            return
        } catch {
            guard !Task.isCancelled, requestID == translationRequestID else { return }
            guard requestStillMatches(
                sourceText: requestedSourceText,
                sourceLanguage: requestedSourceLanguage,
                targetLanguage: requestedTargetLanguage,
                serviceType: requestedServiceType
            ) else {
                isTranslating = false
                return
            }
            translatedText = ""
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }

    func clearSourceText() {
        translationRequestID += 1
        pendingAppleRequest = nil
        appleTranslationConfiguration = nil
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        isTranslating = false
    }

    func selectProvider(_ id: String) async {
        selectedProviderID = id
        translationServiceType = .deepSeek
        translationRequestID += 1
        pendingAppleRequest = nil
        translatedText = ""
        errorMessage = nil
        if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await translate() }
    }

    func selectService(_ serviceType: TranslationServiceType) async {
        guard serviceType != translationServiceType else { return }

        translationRequestID += 1
        pendingAppleRequest = nil
        translationServiceType = serviceType
        translatedText = ""
        errorMessage = nil
        isTranslating = false

        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await translate()
    }

    func translateWithAppleSession(_ session: TranslationSession) async {
        guard let request = pendingAppleRequest else { return }

        do {
            let response = try await session.translate(request.text)
            guard !Task.isCancelled, request.requestID == translationRequestID else { return }
            guard requestStillMatches(
                sourceText: request.text,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage,
                serviceType: request.serviceType
            ) else {
                isTranslating = false
                return
            }
            translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = translatedText.isEmpty ? "Apple Translation 返回了空翻译结果" : nil
        } catch is CancellationError {
            guard request.requestID == translationRequestID else { return }
            isTranslating = false
            return
        } catch {
            guard !Task.isCancelled, request.requestID == translationRequestID else { return }
            guard requestStillMatches(
                sourceText: request.text,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage,
                serviceType: request.serviceType
            ) else {
                isTranslating = false
                return
            }
            translatedText = ""
            errorMessage = appleTranslationErrorMessage(error)
        }

        pendingAppleRequest = nil
        isTranslating = false
    }

    func swapLanguages() {
        guard sourceLanguage != .auto, !translatedText.isEmpty else { return }

        let oldSourceLanguage = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = oldSourceLanguage

        let oldSourceText = sourceText
        sourceText = translatedText
        translatedText = oldSourceText
        errorMessage = nil
    }

    func copyTranslatedText() {
        guard !translatedText.isEmpty else { return }

        pasteboardWriter(translatedText)
    }

    private static func writeStringToGeneralPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.writeObjects([text as NSString]) {
            NSPasteboard.general.declareTypes([.string], owner: nil)
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func requestStillMatches(
        sourceText requestedSourceText: String,
        sourceLanguage requestedSourceLanguage: TranslationLanguage,
        targetLanguage requestedTargetLanguage: TranslationLanguage,
        serviceType requestedServiceType: TranslationServiceType
    ) -> Bool {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines) == requestedSourceText
            && sourceLanguage == requestedSourceLanguage
            && targetLanguage == requestedTargetLanguage
            && translationServiceType == requestedServiceType
    }

    private func appleTranslationErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty || message == "无法翻译" {
            return "Apple Translation 暂时无法翻译当前内容，请手动选择源语言，或切换 Google/已配置 API。"
        }
        return "Apple Translation：\(message)"
    }

    private struct TranslationRequestSnapshot {
        let requestID: Int
        let text: String
        let sourceLanguage: TranslationLanguage
        let targetLanguage: TranslationLanguage
        let serviceType: TranslationServiceType
    }
}
