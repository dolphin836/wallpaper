import AppKit
import SwiftUI

// ─── AppearancePref ──────────────────────────────────────────────
// Persisted via @AppStorage so the choice survives relaunches.
// Applied at the WindowGroup root via `.preferredColorScheme`.
enum AppearancePref: String, CaseIterable {
    case system, light, dark

    static let storageKey = "app.appearance"

    var label: String {
        switch self {
        case .system: L10n.settings.themeSystem
        case .light:  L10n.settings.themeLight
        case .dark:   L10n.settings.themeDark
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    static func fromStorage(_ raw: String) -> AppearancePref {
        AppearancePref(rawValue: raw) ?? .system
    }

    static func applyToApp(_ raw: String) {
        NSApp.appearance = fromStorage(raw).nsAppearance
    }
}
