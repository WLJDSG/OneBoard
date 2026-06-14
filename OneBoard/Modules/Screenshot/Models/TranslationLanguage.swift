import Foundation

/// 翻译面板支持的语言选项。
enum TranslationLanguage: String, Identifiable, Equatable, CaseIterable {
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
        case .auto:
            return "自动检测"
        case .english:
            return "英文"
        case .simplifiedChinese:
            return "中文（简体）"
        case .traditionalChinese:
            return "中文（繁体）"
        case .japanese:
            return "日文"
        case .korean:
            return "韩文"
        case .french:
            return "法文"
        case .german:
            return "德文"
        }
    }

    static var sourceOptions: [TranslationLanguage] {
        allCases
    }

    static var targetOptions: [TranslationLanguage] {
        allCases.filter { $0 != .auto }
    }

    static var sourceDefault: TranslationLanguage {
        sourceDefault(defaults: .standard)
    }

    static var targetDefault: TranslationLanguage {
        targetDefault(defaults: .standard)
    }

    static func sourceDefault(defaults: UserDefaults) -> TranslationLanguage {
        guard let rawValue = defaults.string(forKey: Constants.UserDefaultsKeys.translationSourceLanguage) else {
            return .auto
        }
        return TranslationLanguage(rawValue: rawValue) ?? .auto
    }

    static func targetDefault(defaults: UserDefaults) -> TranslationLanguage {
        guard
            let rawValue = defaults.string(forKey: Constants.UserDefaultsKeys.translationTargetLanguage),
            let language = TranslationLanguage(rawValue: rawValue),
            language != .auto
        else {
            return .english
        }
        return language
    }

    static func inferredSource(for text: String) -> TranslationLanguage? {
        let scalars = text.unicodeScalars.filter {
            !$0.properties.isWhitespace && !CharacterSet.punctuationCharacters.contains($0)
        }
        guard !scalars.isEmpty else { return nil }

        if scalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) {
            return .simplifiedChinese
        }
        if scalars.contains(where: { (0x3040...0x30FF).contains(Int($0.value)) }) {
            return .japanese
        }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains(Int($0.value)) }) {
            return .korean
        }
        if scalars.contains(where: { CharacterSet.letters.contains($0) }) {
            return .english
        }
        return nil
    }
}
