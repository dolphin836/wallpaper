import SwiftUI
import AppKit

// Color + Font tokens lifted from docs/design_handoff_macos/README.md.
// Values are RGB approximations of the OKLCH design tokens used by the web
// app, so the two surfaces read as the same paper/ink palette without
// requiring colour-managed pipelines on this side.
private extension NSAppearance {
    var wallxIsDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension Color {
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.wallxIsDark ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    static func adaptiveRGBA(light: (Double, Double, Double, Double), dark: (Double, Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgba = appearance.wallxIsDark ? dark : light
            return NSColor(srgbRed: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3)
        })
    }

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

    static let paper      = Color.adaptive(light: (0.972, 0.964, 0.945), dark: (0.025, 0.048, 0.060))
    static let paper2     = Color.adaptive(light: (0.948, 0.940, 0.921), dark: (0.065, 0.091, 0.104))
    static let hair       = Color.adaptive(light: (0.872, 0.862, 0.846), dark: (0.137, 0.165, 0.179))
    static let ink        = Color.adaptive(light: (0.176, 0.170, 0.164), dark: (0.915, 0.939, 0.952))
    static let ink2       = Color.adaptive(light: (0.286, 0.278, 0.270), dark: (0.745, 0.774, 0.790))
    static let muted      = Color.adaptive(light: (0.524, 0.516, 0.504), dark: (0.499, 0.532, 0.549))
    static let accent     = Color.adaptive(light: (0.886, 0.491, 0.282), dark: (1.000, 0.435, 0.155))
    static let accentSoft = Color.adaptive(light: (0.957, 0.911, 0.866), dark: (0.281, 0.092, 0.010))
    static let accentInk  = Color.adaptive(light: (0.553, 0.293, 0.149), dark: (1.000, 0.748, 0.552))
    static let warn       = Color.adaptive(light: (0.604, 0.416, 0.094), dark: (0.934, 0.694, 0.248))
    static let lightText  = Color(red: 0.972, green: 0.964, blue: 0.945)
    static let chromePanel = Color.adaptiveRGBA(light: (0.972, 0.964, 0.945, 0.10), dark: (0.025, 0.048, 0.060, 0.62))
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
