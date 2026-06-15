import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHans
    case zhHant
    case ja

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        }
    }

    static func fromStorage(_ raw: String?) -> AppLanguage {
        guard let raw, let value = AppLanguage(rawValue: raw) else { return .system }
        return value
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return .zhHant
        }
        if preferred.hasPrefix("zh") {
            return .zhHans
        }
        if preferred.hasPrefix("ja") {
            return .ja
        }
        return .en
    }

    var acceptLanguageTag: String {
        switch resolved {
        case .system, .en: return "en"
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        case .ja: return "ja"
        }
    }
}

enum AppearancePref: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func fromStorage(_ raw: String?) -> AppearancePref {
        guard let raw, let value = AppearancePref(rawValue: raw) else { return .system }
        return value
    }
}

// Session-wide presentation switches driven from the top toolbar.
@MainActor
@Observable
final class UIPrefs {
    static let shared = UIPrefs()

    private static let lockPreviewKey = "ios.lockPreview"
    private static let languageKey = "ios.language"
    private static let appearanceKey = "ios.appearance"

    // When on, every wallpaper tile renders the lock-screen mock overlay
    // (clock + flashlight/camera pills) so users can judge how a
    // wallpaper actually reads behind iOS lock chrome.
    var lockPreview: Bool {
        didSet { UserDefaults.standard.set(lockPreview, forKey: Self.lockPreviewKey) }
    }

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }

    var appearance: AppearancePref {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    private init() {
        lockPreview = UserDefaults.standard.bool(forKey: Self.lockPreviewKey)
        language = AppLanguage.fromStorage(UserDefaults.standard.string(forKey: Self.languageKey))
        appearance = AppearancePref.fromStorage(UserDefaults.standard.string(forKey: Self.appearanceKey))
    }
}
