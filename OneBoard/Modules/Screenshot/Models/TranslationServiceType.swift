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
            return "自定义 API"
        }
    }

    var settingsDisplayName: String {
        switch self {
        case .apple:
            return "Apple Translation"
        case .google:
            return "Google 翻译"
        case .deepSeek:
            return "自定义 API"
        }
    }

    var requiresAPIKey: Bool {
        self == .deepSeek
    }

    static func current(defaults: UserDefaults = .standard) -> TranslationServiceType {
        let rawValue = defaults.string(forKey: Constants.UserDefaultsKeys.translationServiceType)
        if rawValue == "third_party" {
            return .deepSeek
        }
        return TranslationServiceType(rawValue: rawValue ?? "") ?? .apple
    }
}
