import SwiftUI

// Singleton palette source. Tiles call apply() on hover, the page-mesh
// background view observes this and re-renders its blurred radial
// gradient with the wallpaper's palette colors. Clears back to the
// warm-brand defaults when no tile is hovered.
//
// Same model the web uses (--d3-c1/c2/c3 CSS custom properties + a
// fixed-position blurred mesh layer), just pushed through SwiftUI's
// observation system instead of inline style attributes.
@MainActor
@Observable
final class PaletteEnv {
    static let shared = PaletteEnv()

    // Three stops drive the mesh. When `palette` is empty we render
    // the warm brand defaults; otherwise we map to 3 of the parsed
    // hex strings (same indexing the web uses — index 1 / second-to-
    // last / last).
    var c1: Color = .brandPaletteC1
    var c2: Color = .brandPaletteC2
    var c3: Color = .brandPaletteC3
    var dominant: Color? = nil
    var isDefault = true

    func apply(palette raw: String?, dominant rawDominant: String?) {
        isDefault = false
        if let rawDominant, !rawDominant.isEmpty {
            dominant = Color(hex: rawDominant)
        }
        guard let raw, !raw.isEmpty else {
            // Fall back to dominant if no full palette was provided —
            // gives every tile *something* to react with, even when
            // the lighter Wallpaper shape only carries a dominant_color.
            if let rawDominant, !rawDominant.isEmpty {
                let d = Color(hex: rawDominant)
                c1 = d.opacity(0.85); c2 = d.opacity(0.55); c3 = d.opacity(0.4)
            } else {
                resetToDefaults()
            }
            return
        }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 3 else {
            resetToDefaults()
            return
        }
        c1 = Color(hex: parts[parts.count - 2])
        c2 = Color(hex: parts[1])
        c3 = Color(hex: parts[parts.count - 1])
    }

    func resetToDefaults() {
        isDefault = true
        c1 = .brandPaletteC1
        c2 = .brandPaletteC2
        c3 = .brandPaletteC3
        dominant = nil
    }
}

extension Color {
    // Warm peach / sand / terracotta — matches the web's d3-c1/2/3
    // defaults so the mesh reads as the same product surface.
    static let brandPaletteC1 = Color.adaptive(light: (0.94, 0.78, 0.55), dark: (0.257, 0.112, 0.076))
    static let brandPaletteC2 = Color.adaptive(light: (0.95, 0.74, 0.62), dark: (0.011, 0.117, 0.163))
    static let brandPaletteC3 = Color.adaptive(light: (0.96, 0.84, 0.66), dark: (0.308, 0.151, 0.052))
}

// Fixed-position blurred mesh, mirrors .d3-discover-mesh in
// index.css. Three radial blobs at the same anchors the web uses
// (22/30, 78/20, 50/82) heavily blurred to bleed into each other.
struct PageMesh: View {
    @State private var env = PaletteEnv.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let r = max(proxy.size.width, proxy.size.height)
            let dark = colorScheme == .dark
            ZStack {
                LinearGradient(
                    colors: [
                        Color.paper.blended(with: env.c1, fraction: 0.20),
                        Color.paper.blended(with: env.c2, fraction: 0.14),
                        Color.paper.blended(with: env.c3, fraction: 0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ZStack {
                    RadialGradient(colors: [env.c1, .clear],
                                   center: UnitPoint(x: 0.22, y: 0.30),
                                   startRadius: 0, endRadius: r * 0.45)
                    RadialGradient(colors: [env.c2, .clear],
                                   center: UnitPoint(x: 0.78, y: 0.20),
                                   startRadius: 0, endRadius: r * 0.50)
                    RadialGradient(colors: [env.c3, .clear],
                                   center: UnitPoint(x: 0.50, y: 0.82),
                                   startRadius: 0, endRadius: r * 0.55)
                }
                .blur(radius: 80)
                .saturation(dark ? 2.0 : 1.4)
                .opacity(dark ? 0.72 : 0.58)
            }
            .animation(.easeOut(duration: 0.42), value: env.c1)
            .animation(.easeOut(duration: 0.42), value: env.c2)
            .animation(.easeOut(duration: 0.42), value: env.c3)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
