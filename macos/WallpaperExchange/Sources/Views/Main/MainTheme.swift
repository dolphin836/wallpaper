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

// Shared window-chrome constants for the manual split layout.
//
// The title bar is hidden via .windowStyle(.hiddenTitleBar) +
// .fullSizeContentView, so the content view fills the whole window and
// the traffic lights float at the natural top-left. We paint a paper
// "top bar" of height `topBar` across the window top — the traffic
// lights sit on it — and below it float a Liquid-Glass sidebar card
// (inset on all sides, rounded, bordered) next to the full-bleed
// detail surface (rounded only on its top-leading corner).
// Live geometry of the native traffic-light buttons, measured in AppKit
// (AppDelegate) and published so the SwiftUI sidebar toggle can sit
// perfectly aligned with them — same row, same size.
final class WindowMetrics: ObservableObject {
    static let shared = WindowMetrics()
    @Published var trafficCenterY: CGFloat = 14   // from the window's top
    @Published var trafficTrailingX: CGFloat = 70 // right edge from window's left
    @Published var trafficDotSize: CGFloat = 14   // button diameter

    func update(centerY: CGFloat, trailingX: CGFloat, dot: CGFloat) {
        if abs(centerY - trafficCenterY) > 0.5 { trafficCenterY = centerY }
        if abs(trailingX - trafficTrailingX) > 0.5 { trafficTrailingX = trailingX }
        if dot > 1, abs(dot - trafficDotSize) > 0.5 { trafficDotSize = dot }
    }
}

enum WindowChrome {
    /// Height of the paper top bar the traffic lights float on, above
    /// the sidebar card and the detail surface.
    static let topBar: CGFloat = 38
    /// Gap between the window edges (and the two panes) and the
    /// floating sidebar card.
    static let inset: CGFloat = 10
    /// Corner radius of the sidebar card and the detail surface's
    /// top-leading corner.
    static let radius: CGFloat = 14
    /// Top padding for the first row of content measured from its own
    /// surface top (sidebar logo, detail-pane hero). The top bar is
    /// already accounted for by the layout, so this is just breathing
    /// room inside each panel.
    static let topInset: CGFloat = 20
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
