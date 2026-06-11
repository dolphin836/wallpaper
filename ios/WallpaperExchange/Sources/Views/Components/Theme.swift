import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Archive palette — the same paper/ink/warm-accent tokens the web app
// (OKLCH) and the Mac client (MacTheme.swift) use, so all three surfaces
// read as one product. Values are sRGB approximations of the design
// hand-off tokens; adaptive light/dark via trait resolution.
extension Color {
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #endif
    }

    static let paper      = Color.adaptive(light: (0.972, 0.964, 0.945), dark: (0.018, 0.025, 0.030))
    static let paper2     = Color.adaptive(light: (0.948, 0.940, 0.921), dark: (0.047, 0.057, 0.064))
    static let paper3     = Color.adaptive(light: (0.922, 0.912, 0.892), dark: (0.074, 0.086, 0.094))
    static let hair       = Color.adaptive(light: (0.872, 0.862, 0.846), dark: (0.196, 0.216, 0.228))
    static let ink        = Color.adaptive(light: (0.176, 0.170, 0.164), dark: (0.928, 0.941, 0.948))
    static let ink2       = Color.adaptive(light: (0.286, 0.278, 0.270), dark: (0.730, 0.754, 0.766))
    static let muted      = Color.adaptive(light: (0.524, 0.516, 0.504), dark: (0.536, 0.570, 0.588))
    static let accent     = Color.adaptive(light: (0.886, 0.491, 0.282), dark: (1.000, 0.435, 0.155))
    static let accentSoft = Color.adaptive(light: (0.957, 0.911, 0.866), dark: (0.281, 0.092, 0.010))
    static let accentInk  = Color.adaptive(light: (0.553, 0.293, 0.149), dark: (1.000, 0.748, 0.552))
    static let warn       = Color.adaptive(light: (0.604, 0.416, 0.094), dark: (0.934, 0.694, 0.248))
    // Paper-toned text for chips drawn over imagery, both schemes.
    static let lightText  = Color(red: 0.972, green: 0.964, blue: 0.945)
}

// Editorial type ramp: serif display for page/section titles only,
// mono caps for metadata (resolution, kickers, technical labels),
// system sans for everything interactive.
extension Font {
    static let display28 = Font.system(size: 28, weight: .semibold, design: .serif)
    static let display22 = Font.system(size: 22, weight: .semibold, design: .serif)
    static let display18 = Font.system(size: 18, weight: .semibold, design: .serif)
    static let kicker    = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let mono10    = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let mono11    = Font.system(size: 11, weight: .medium, design: .monospaced)
}

// Uppercase letter-spaced mono label — mirrors the web's .kicker class
// and the Mac client's Kicker view.
struct Kicker: View {
    var text: String
    var tint: Color = .muted

    var body: some View {
        Text(text.uppercased())
            .font(.kicker)
            .tracking(2.0)
            .foregroundStyle(tint)
    }
}

// Mono-caps chip drawn over imagery (resolution / LIVE / AI badges).
struct MediaChip: View {
    var text: String
    var tint: Color = Color.black.opacity(0.55)

    var body: some View {
        Text(text.uppercased())
            .font(.mono10)
            .tracking(0.5)
            .foregroundStyle(Color.lightText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(tint, in: Capsule())
    }
}

// Hairline-bordered paper card backdrop, the archive's default surface
// treatment (border + spacing, not shadow).
struct PaperCard: ViewModifier {
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(Color.paper2, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.hair, lineWidth: 1)
            )
    }
}

extension View {
    func paperCard(radius: CGFloat = 12) -> some View {
        modifier(PaperCard(radius: radius))
    }
}
