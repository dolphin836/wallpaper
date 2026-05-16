import SwiftUI
import AppKit

// Color + Font tokens lifted from docs/design_handoff_macos/README.md.
// Values are RGB approximations of the OKLCH design tokens used by the web
// app, so the two surfaces read as the same paper/ink palette without
// requiring colour-managed pipelines on this side.
extension Color {
    // Parses a "#RRGGBB" string into a Color. Used for dominant-color
    // placeholder fills on tiles before the image decodes.
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var raw: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&raw)
        let r, g, b: Double
        if trimmed.count == 6 {
            r = Double((raw >> 16) & 0xFF) / 255
            g = Double((raw >> 8) & 0xFF) / 255
            b = Double(raw & 0xFF) / 255
        } else {
            r = 0.9; g = 0.9; b = 0.9
        }
        self.init(red: r, green: g, blue: b)
    }

    static let paper      = Color(red: 0.972, green: 0.964, blue: 0.945)
    static let paper2     = Color(red: 0.948, green: 0.940, blue: 0.921)
    static let hair       = Color(red: 0.872, green: 0.862, blue: 0.846)
    static let ink        = Color(red: 0.176, green: 0.170, blue: 0.164)
    static let ink2       = Color(red: 0.286, green: 0.278, blue: 0.270)
    static let muted      = Color(red: 0.524, green: 0.516, blue: 0.504)
    static let accent     = Color(red: 0.886, green: 0.491, blue: 0.282)
    static let accentSoft = Color(red: 0.957, green: 0.911, blue: 0.866)
    static let accentInk  = Color(red: 0.553, green: 0.293, blue: 0.149)
    static let warn       = Color(red: 0.604, green: 0.416, blue: 0.094)
}

// Editorial type ramp. We deliberately don't bundle Instrument Serif or
// JetBrains Mono — design hand-off says system serif/monospaced fallback
// is acceptable, and bundling TTFs adds ~1MB to the app for marginal
// visual gain at the small sizes used in the popover.
extension Font {
    static let displayLg = Font.system(size: 18, design: .serif)
    static let displayMd = Font.system(size: 17, design: .serif)
    static let displaySm = Font.system(size: 14, design: .serif)
    static let monoCaps  = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let monoLabel = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let sans12    = Font.system(size: 12, weight: .regular)
    static let sans11    = Font.system(size: 11, weight: .medium)
    static let sans10    = Font.system(size: 10, weight: .medium)
}

// NSVisualEffectView wrapper. The popover background needs the
// frosted-glass paper feel described in the hand-off — translucent
// paper-tinted material with system vibrancy. .hudWindow gives the
// closest match to the design's "paper at 94% with blur(28px)
// saturate(1.4)".
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
