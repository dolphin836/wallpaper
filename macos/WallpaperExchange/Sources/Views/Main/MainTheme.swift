import SwiftUI
import AppKit

// Extends the existing MacTheme palette (Color.paper / ink / accent /
// hair, Font.displayLg / monoCaps) with the bigger display sizes and
// helper tokens the v2 main window needs. Keeping the production
// tokens in one extension makes it obvious which sizes are 'new for
// the main window' vs. 'existing popover'.
extension Color {
    static let paper3   = Color(red: 0.922, green: 0.912, blue: 0.892)
    static let hairSoft = Color(red: 0.902, green: 0.892, blue: 0.876)
    static let muted2   = Color(red: 0.700, green: 0.692, blue: 0.680)
}

extension Font {
    static let display32 = Font.system(size: 32, weight: .semibold, design: .serif)
    static let display24 = Font.system(size: 24, weight: .semibold, design: .serif)
    static let display20 = Font.system(size: 20, weight: .semibold, design: .serif)
    // displayLg / displayMd / displaySm already exist in MacTheme (18 / 17 / 14).
    static let kicker    = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let mono10    = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let mono11    = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let sans13    = Font.system(size: 13, weight: .regular)
}

// Small editorial kicker — uppercase, letter-spaced mono caps. Mirrors
// the web's .kicker class.
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

// In-place flow layout for tag chips (wraps multi-line). macOS 14
// gives us the Layout protocol so no UIKit shim required.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                widest = max(widest, x - spacing); x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: widest, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// Shared window-chrome constants. The title bar is hidden via
// .windowStyle(.hiddenTitleBar) + .fullSizeContentView so content
// extends to the very top of the window. The sidebar logo sits on
// the SAME ROW as the traffic-light buttons (red/yellow/green) —
// the logo is offset right by `trafficLightInset` to clear them.
// Detail content drops by the same `topInset` so the hero and the
// logo share a baseline.
enum WindowChrome {
    /// Top padding shared by sidebar logo and detail pane first row.
    /// 10pt lines the logo's vertical center up with the traffic
    /// lights (which sit at y ≈ 8–22 in the window).
    static let topInset: CGFloat = 10

    /// Left padding the sidebar logo needs to clear the three
    /// traffic-light buttons. They occupy x ≈ 10–66 in the window;
    /// 72pt leaves a 6pt gap before the logo starts.
    static let trafficLightInset: CGFloat = 72
}

extension Color {
    // RGB-space blend for chip tinting. Tag chips lean toward ink so
    // they stay legible while still palette-coloured.
    func blended(with other: Color, fraction: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let r = a.redComponent   * (1 - fraction) + b.redComponent   * fraction
        let g = a.greenComponent * (1 - fraction) + b.greenComponent * fraction
        let bl = a.blueComponent * (1 - fraction) + b.blueComponent  * fraction
        return Color(red: r, green: g, blue: bl)
    }
}
