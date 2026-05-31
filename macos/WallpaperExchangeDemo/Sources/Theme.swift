import SwiftUI
import AppKit

// Design tokens ported from the web's Liquid Surface theme. Same OKLCH
// values used by the production menu-bar popover so the redesigned
// main window reads as part of the same product.
extension Color {
    static let dPaper      = Color(red: 0.972, green: 0.964, blue: 0.945)
    static let dPaper2     = Color(red: 0.948, green: 0.940, blue: 0.921)
    static let dPaper3     = Color(red: 0.922, green: 0.912, blue: 0.892)
    static let dHair       = Color(red: 0.872, green: 0.862, blue: 0.846)
    static let dHairSoft   = Color(red: 0.902, green: 0.892, blue: 0.876)
    static let dInk        = Color(red: 0.176, green: 0.170, blue: 0.164)
    static let dInk2       = Color(red: 0.286, green: 0.278, blue: 0.270)
    static let dMuted      = Color(red: 0.524, green: 0.516, blue: 0.504)
    static let dMuted2     = Color(red: 0.700, green: 0.692, blue: 0.680)
    static let dAccent     = Color(red: 0.886, green: 0.491, blue: 0.282)
    static let dAccentSoft = Color(red: 0.957, green: 0.911, blue: 0.866)
    static let dAccentInk  = Color(red: 0.553, green: 0.293, blue: 0.149)
}

extension Font {
    // Editorial display ramp — system serif so we don't bundle TTFs
    // for what's still a preview build.
    static let dDisplay32 = Font.system(size: 32, weight: .semibold, design: .serif)
    static let dDisplay24 = Font.system(size: 24, weight: .semibold, design: .serif)
    static let dDisplay18 = Font.system(size: 18, weight: .semibold, design: .serif)
    static let dDisplay16 = Font.system(size: 16, weight: .semibold, design: .serif)

    static let dKicker    = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let dMono11    = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let dMono10    = Font.system(size: 10, weight: .medium, design: .monospaced)

    static let dSans13    = Font.system(size: 13, weight: .regular)
    static let dSans12    = Font.system(size: 12, weight: .medium)
    static let dSans11    = Font.system(size: 11, weight: .medium)
}

// Frosted backdrop the main window sits on. .underWindowBackground gives
// us the Big Sur-style translucent paper feel without our own blur math.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

// Mesh tint built from a wallpaper's dominant color. Used as the page
// backdrop on the detail inspector + sometimes on the Discover hero.
struct DominantMesh: View {
    var color: Color
    var body: some View {
        ZStack {
            color.opacity(0.20)
            RadialGradient(colors: [color.opacity(0.35), .clear], center: .topLeading, startRadius: 20, endRadius: 600)
            RadialGradient(colors: [color.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 600)
        }
    }
}

// Editorial kicker label — small, mono, uppercase, letter-spaced.
struct Kicker: View {
    var text: String
    var tint: Color = .dMuted
    var body: some View {
        Text(text.uppercased())
            .font(.dKicker)
            .tracking(2.0)
            .foregroundStyle(tint)
    }
}
