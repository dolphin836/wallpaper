import Foundation

// UI localization core. Translations are compiled into the binary as Swift
// structs (one file per namespace under Sources/L10n/) instead of .lproj
// resources — Package.swift deliberately ships no resource bundle (see the
// 1.2.2 Bundle.module packaging incident), and struct memberwise inits give
// the same "missing key fails the build" guarantee the web client gets from
// its `typeof en` locale typing.
//
// Reactivity: views never observe this directly. MainWindowRoot applies
// LanguagePref and re-mounts the whole tree via .id(languageRaw), so every
// view re-reads L10n.<ns>.<key> on a language switch. AppKit surfaces
// (status-bar menu, alerts) are built per presentation and pick up the
// language naturally.

enum Lang: String, CaseIterable {
    case en
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case ja

    /// Native-script display name — shown as-is in the picker, never translated.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .zhCN: "简体中文"
        case .zhTW: "繁體中文"
        case .ja: "日本語"
        }
    }
}

enum LanguagePref: String, CaseIterable {
    case system
    case en
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case ja

    static let storageKey = "wpe_language"

    static func fromStorage(_ raw: String) -> LanguagePref {
        LanguagePref(rawValue: raw) ?? .system
    }

    /// Maps the pref onto a concrete language, falling back to the system
    /// locale (zh-Hant/TW/HK/MO → Traditional, other zh → Simplified).
    var resolved: Lang {
        switch self {
        case .en: return .en
        case .zhCN: return .zhCN
        case .zhTW: return .zhTW
        case .ja: return .ja
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("zh") {
                let traditional = preferred.contains("hant") || preferred.contains("tw")
                    || preferred.contains("hk") || preferred.contains("mo")
                return traditional ? .zhTW : .zhCN
            }
            if preferred.hasPrefix("ja") { return .ja }
            return .en
        }
    }

    /// Resolve + publish to L10n. Mirrors AppearancePref.applyToApp —
    /// called from MainWindowRoot onAppear/onChange before the .id() remount.
    static func applyToApp(_ raw: String) {
        L10n.lang = fromStorage(raw).resolved
    }
}

enum L10n {
    /// The resolved UI language. Defaults to the system mapping so strings
    /// rendered before MainWindowRoot mounts (status-bar menu, update
    /// alerts at launch) are already localized.
    static var lang: Lang = LanguagePref.fromStorage(
        UserDefaults.standard.string(forKey: LanguagePref.storageKey) ?? LanguagePref.system.rawValue
    ).resolved
}
