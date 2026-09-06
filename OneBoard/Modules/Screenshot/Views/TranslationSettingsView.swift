import SwiftUI

enum TranslationProviderPreset: String, CaseIterable, Identifiable {
    case custom
    case deepSeek
    case openRouter
    case siliconFlow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: return "自定义"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        case .siliconFlow: return "SiliconFlow"
        }
    }
    var baseURL: String {
        switch self {
        case .custom: return ""
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        }
    }
    var model: String {
        switch self {
        case .custom: return ""
        case .deepSeek: return "deepseek-chat"
        case .openRouter: return "openai/gpt-4o-mini"
        case .siliconFlow: return "Qwen/Qwen2.5-7B-Instruct"
        }
    }
}

struct TranslationSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.translationServiceType) private var serviceType = TranslationServiceType.apple.rawValue
    @AppStorage(ConfiguredAITranslationService.selectionKey) private var providerID = ""
    @AppStorage(Constants.UserDefaultsKeys.translationSourceLanguage) private var sourceLanguage = ""
    @AppStorage(Constants.UserDefaultsKeys.translationTargetLanguage) private var targetLanguage = "zh-Hans"
    @ObservedObject private var providers = AIModelSwitcherViewModel.shared
    @State private var adding = false
    private var customProfiles: [AIProviderProfile] { providers.profiles.filter { $0.kind == .custom } }
    var body: some View {
        SettingsForm {
            Section {
                Picker("翻译引擎", selection: $serviceType) {
                    Text("系统翻译").tag(TranslationServiceType.apple.rawValue)
                    Text("Google").tag(TranslationServiceType.google.rawValue)
                    Text("自定义 API").tag(TranslationServiceType.deepSeek.rawValue)
                }.pickerStyle(.segmented)
            } header: { Text("翻译引擎") }
            if serviceType == TranslationServiceType.deepSeek.rawValue || serviceType == "third_party" {
                Section {
                    Picker("AI 模型配置", selection: $providerID) {
                        Text("请选择已配置的 AI 模型").tag("")
                        ForEach(customProfiles) { profile in
                            Text("\(profile.title) · \(profile.model)").tag(profile.id.uuidString)
                        }
                    }
                    if let profile = customProfiles.first(where: { $0.id.uuidString == providerID }) {
                        LabeledContent("模型", value: profile.model)
                        LabeledContent("接口", value: profile.baseURL)
                        Text("使用此配置保存的 Key、模型和协议；不会切换 Codex 或 Claude 的活动配置。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !providerID.isEmpty {
                        Text("原配置已删除，请重新选择。").foregroundStyle(.orange)
                    }
                    Button("新增 AI 模型") { adding = true }
                } header: { Text("自定义 API") }
            }
            Section {
                languagePicker("源语言", selection: $sourceLanguage, auto: true)
                languagePicker("目标语言", selection: $targetLanguage, auto: false)
            } header: { Text("翻译语言") }
        }
        .sheet(isPresented: $adding) {
            AIProviderEditorView(client: .codex, profile: nil, savedAPIKey: nil, allowsSwitch: false) { profile, key in
                try await providers.save(profile, apiKey: key)
                providerID = profile.id.uuidString
                adding = false
            } onSaveAndSwitch: { _, _ in
            } onCancel: { adding = false }
        }
        .onAppear { providers.reload() }
    }
    private func languagePicker(_ title: String, selection: Binding<String>, auto: Bool) -> some View {
        Picker(title, selection: selection) {
            if auto { Text("自动检测").tag("") }
            Text("简体中文").tag("zh-Hans"); Text("繁体中文").tag("zh-Hant")
            Text("英语").tag("en"); Text("日语").tag("ja"); Text("韩语").tag("ko")
            Text("法语").tag("fr"); Text("德语").tag("de")
        }
    }
}
