import Foundation
import SwiftUI

enum GenerativePreset: String, CaseIterable, Identifiable, Codable {
    case starfield
    case rain
    case campfire
    case fireflies

    var id: String { rawValue }

    var shaderIndex: UInt32 {
        switch self {
        case .starfield: 0
        case .rain: 1
        case .campfire: 2
        case .fireflies: 3
        }
    }

    var title: String {
        switch self {
        case .starfield: L10n.generative.starfieldTitle
        case .rain: L10n.generative.rainTitle
        case .campfire: L10n.generative.campfireTitle
        case .fireflies: L10n.generative.firefliesTitle
        }
    }

    var subtitle: String {
        switch self {
        case .starfield: L10n.generative.starfieldSubtitle
        case .rain: L10n.generative.rainSubtitle
        case .campfire: L10n.generative.campfireSubtitle
        case .fireflies: L10n.generative.firefliesSubtitle
        }
    }

    var description: String {
        switch self {
        case .starfield: L10n.generative.starfieldDescription
        case .rain: L10n.generative.rainDescription
        case .campfire: L10n.generative.campfireDescription
        case .fireflies: L10n.generative.firefliesDescription
        }
    }

    var atmosphere: String {
        switch self {
        case .starfield: L10n.generative.starfieldAtmosphere
        case .rain: L10n.generative.rainAtmosphere
        case .campfire: L10n.generative.campfireAtmosphere
        case .fireflies: L10n.generative.firefliesAtmosphere
        }
    }

    var symbol: String {
        switch self {
        case .starfield: "sparkles"
        case .rain: "cloud.rain"
        case .campfire: "flame"
        case .fireflies: "lightbulb.min"
        }
    }

    var accent: Color {
        switch self {
        case .starfield: Color(red: 0.41, green: 0.62, blue: 1.0)
        case .rain: Color(red: 0.28, green: 0.75, blue: 0.92)
        case .campfire: Color(red: 1.0, green: 0.43, blue: 0.12)
        case .fireflies: Color(red: 0.78, green: 0.92, blue: 0.28)
        }
    }

    var palette: [Color] {
        switch self {
        case .starfield:
            [Color(hex: "050816"), Color(hex: "102B57"), Color(hex: "A7CEFF")]
        case .rain:
            [Color(hex: "06141F"), Color(hex: "123D55"), Color(hex: "64C5DD")]
        case .campfire:
            [Color(hex: "080506"), Color(hex: "7B1E12"), Color(hex: "FFB735")]
        case .fireflies:
            [Color(hex: "071713"), Color(hex: "174936"), Color(hex: "D7F063")]
        }
    }
}

struct GenerativeWallpaperSettings: Codable, Equatable {
    var intensity: Float = 0.82
    var speed: Float = 0.72

    static let standard = GenerativeWallpaperSettings()
}
