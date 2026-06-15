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

    // Warm peach / sand / terracotta defaults shared by the web and Mac
    // mesh background before a wallpaper card lends it a palette.
    static let brandPaletteC1 = Color.adaptive(light: (0.940, 0.780, 0.550), dark: (0.168, 0.074, 0.052))
    static let brandPaletteC2 = Color.adaptive(light: (0.950, 0.740, 0.620), dark: (0.016, 0.084, 0.116))
    static let brandPaletteC3 = Color.adaptive(light: (0.960, 0.840, 0.660), dark: (0.198, 0.096, 0.042))
}

// Palette source for the iOS ambient mesh. Wallpaper cards call apply()
// on pointer hover; the root background observes these stops and eases
// between the default brand blend and the wallpaper's extracted palette.
@MainActor
@Observable
final class PaletteEnv {
    static let shared = PaletteEnv()

    var c1: Color = .brandPaletteC1
    var c2: Color = .brandPaletteC2
    var c3: Color = .brandPaletteC3
    var revision = 0

    private init() {}

    func apply(palette raw: String?, dominant rawDominant: String?) -> Bool {
        guard let colors = Self.resolvedColors(palette: raw, dominant: rawDominant) else {
            return false
        }

        c1 = colors.0
        c2 = colors.1
        c3 = colors.2
        revision += 1
        return true
    }

    func resetToDefaults() {
        c1 = .brandPaletteC1
        c2 = .brandPaletteC2
        c3 = .brandPaletteC3
        revision += 1
    }

    static func canResolve(palette raw: String?, dominant rawDominant: String?) -> Bool {
        resolvedColors(palette: raw, dominant: rawDominant) != nil
    }

    private static func resolvedColors(palette raw: String?, dominant rawDominant: String?) -> (Color, Color, Color)? {
        let parts = (raw ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if parts.count >= 3,
           let first = Color(hex: parts[0]),
           let middle = Color(hex: parts[parts.count / 2]),
           let last = Color(hex: parts[parts.count - 1]) {
            return (first, middle, last)
        }

        if let rawDominant, let dominant = Color(hex: rawDominant) {
            return (dominant, dominant, dominant)
        }

        return nil
    }
}

struct PageMesh: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var palette = PaletteEnv.shared

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height)
            let isDark = colorScheme == .dark

            ZStack {
                Color.paper

                LinearGradient(
                    colors: [
                        palette.c1.opacity(isDark ? 0.28 : 0.24),
                        palette.c2.opacity(isDark ? 0.22 : 0.18),
                        palette.c3.opacity(isDark ? 0.25 : 0.22),
                        Color.paper.opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ZStack {
                    RadialGradient(
                        colors: [palette.c1.opacity(isDark ? 0.66 : 0.55), .clear],
                        center: UnitPoint(x: 0.18, y: 0.22),
                        startRadius: 0,
                        endRadius: radius * 0.48
                    )
                    RadialGradient(
                        colors: [palette.c2.opacity(isDark ? 0.54 : 0.46), .clear],
                        center: UnitPoint(x: 0.86, y: 0.18),
                        startRadius: 0,
                        endRadius: radius * 0.54
                    )
                    RadialGradient(
                        colors: [palette.c3.opacity(isDark ? 0.60 : 0.50), .clear],
                        center: UnitPoint(x: 0.52, y: 0.88),
                        startRadius: 0,
                        endRadius: radius * 0.62
                    )
                }
                .blur(radius: 76)
                .saturation(isDark ? 1.24 : 1.18)

                if isDark {
                    Color.black.opacity(0.08)
                } else {
                    Color.white.opacity(0.18)
                }
            }
            .animation(.easeOut(duration: 0.42), value: palette.revision)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// Type ramp: script brand voice for page titles, bold sans for content
// headings, mono caps for technical metadata.
extension Font {
    static let display28 = Font.system(size: 28, weight: .semibold, design: .serif)
    static let display22 = Font.system(size: 22, weight: .semibold, design: .serif)
    static let display18 = Font.system(size: 18, weight: .semibold, design: .serif)
    static let kicker    = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let mono10    = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let mono11    = Font.system(size: 11, weight: .medium, design: .monospaced)

    // Brand script for page titles (ships on both iOS and macOS).
    static func script(_ size: CGFloat) -> Font {
        .custom("SnellRoundhand-Black", size: size)
    }
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

// Mono-caps chip drawn over imagery (resolution / AI badges). Frosted
// material under a dark tint so the chip reads on any wallpaper without
// the dead flatness of a plain black pill.
struct MediaChip: View {
    var text: String
    var tint: Color = Color.black.opacity(0.25)

    var body: some View {
        Text(text.uppercased())
            .font(.mono10)
            .tracking(0.5)
            .foregroundStyle(Color.lightText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(tint, in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
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

// Press feedback for every tappable surface: a quick settle-down scale
// with a soft spring back. The single biggest "feels native" win.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

extension View {
    func paletteReactive(palette: String?, dominant: String?) -> some View {
        modifier(PaletteReactive(palette: palette, dominant: dominant))
    }

    // Lightweight iOS-native feedback for stateful controls. The macOS
    // dev preview type-checks the same sources, so keep the modifier
    // platform-gated instead of sprinkling availability checks in pages.
    @ViewBuilder
    func archiveSelectionFeedback<Value: Equatable>(trigger: Value) -> some View {
        #if os(iOS)
        self.sensoryFeedback(.selection, trigger: trigger)
        #else
        self
        #endif
    }

    // A very small scroll response for image cards. It gives the grid a
    // native, tactile read without animating layout or fighting reduce-
    // motion users on non-iOS preview builds.
    @ViewBuilder
    func archiveScrollLift() -> some View {
        #if os(iOS)
        self.scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.985)
                .opacity(phase.isIdentity ? 1 : 0.88)
        }
        #else
        self
        #endif
    }
}

private struct PaletteReactive: ViewModifier {
    let palette: String?
    let dominant: String?

    @State private var active = false

    private var hasUsableColor: Bool {
        PaletteEnv.canResolve(palette: palette, dominant: dominant)
    }

    func body(content: Content) -> some View {
        if hasUsableColor {
            content
                .onHover { hovering in
                    hovering ? activate() : deactivate()
                }
                .onDisappear { deactivate() }
        } else {
            content
        }
    }

    private func activate() {
        guard !active else { return }
        guard PaletteEnv.shared.apply(palette: palette, dominant: dominant) else { return }
        active = true
    }

    private func deactivate() {
        guard active else { return }
        active = false
        PaletteEnv.shared.resetToDefaults()
    }
}
