import Foundation

struct ConfigurationSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schema: Int
    let modifiedAt: Date
    let standardDefaults: Data
    let sharedDefaults: Data
    let privateRecords: [PrivateConfigurationRecord]
    let applicationState: [ApplicationConfigurationRecord]
}

enum ConfigurationSnapshotCodec {
    static let standardKeys: [String] = [
        "calendar.countdowns",
        "macStatus.menuMode", "macStatus.menuIcon", "quickLaunch.bindings",
        Constants.UserDefaultsKeys.maxClipboardItems,
        Constants.UserDefaultsKeys.retentionDays,
        Constants.UserDefaultsKeys.ocrServiceType,
        Constants.UserDefaultsKeys.ocrLanguage,
        Constants.UserDefaultsKeys.translationServiceType,
        Constants.UserDefaultsKeys.translationSourceLanguage,
        Constants.UserDefaultsKeys.translationTargetLanguage,
        Constants.UserDefaultsKeys.todoRetentionDays,
        Constants.UserDefaultsKeys.todoAutoRetractDelay,
        Constants.UserDefaultsKeys.todoShowNotifications,
        ConfiguredAITranslationService.selectionKey,
        Constants.UserDefaultsKeys.calendarWeekStart,
        Constants.UserDefaultsKeys.calendarShowInMenuBar,
    ]

    static let sharedKeys = [Constants.UserDefaultsKeys.enabledFileTypes]

    static func encodeDefaults(_ defaults: UserDefaults, keys: [String]) throws -> Data {
        let exportedKeys = Set(keys).union(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("KeyboardShortcuts_") })
        let values = Dictionary(uniqueKeysWithValues: exportedKeys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        })
        return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    static func applyDefaults(_ data: Data, to defaults: UserDefaults, keys: [String]) throws {
        guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ConfigurationSyncError.invalidSnapshot
        }
        let restoredKeys = Set(keys)
            .union(values.keys.filter { $0.hasPrefix("KeyboardShortcuts_") })
            .union(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("KeyboardShortcuts_") })
        for key in restoredKeys {
            if let value = values[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
}

enum ConfigurationSyncError: LocalizedError, Equatable {
    case invalidSnapshot
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSnapshot: return "iCloud 中的 OneBoard 配置格式无效"
        case .iCloudUnavailable: return "iCloud 当前不可用，请检查系统账号与网络"
        }
    }
}
