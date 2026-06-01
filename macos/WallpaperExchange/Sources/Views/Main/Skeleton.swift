import SwiftUI

// Skeleton placeholder tiles for the Home page sections, mirroring the
// web's <SkeletonTile variant="..."/> from HomePage.tsx + the
// .skeleton-card shimmer in index.css.
//
// Web recipe:
//   1. Tile chrome — same rounded-corner box the real tile uses
//      (h3-tile 16pt or h3-tile-collection 14pt + paper-stack)
//   2. .skeleton-card overlay — a 100deg gradient band
//      (transparent 25% → white(0.45) 50% → transparent 75%) that
//      animates translateX(-100% → 100%) on a 1.6s ease-in-out loop
//
// We approximate the 100deg sweep with topLeading→bottomTrailing
// gradient anchors and shift it horizontally via .offset(x:) on each
// frame change. ShimmerBand below handles the animation.

enum SkeletonVariant {
    case hero        // 16:9, corner 24 — top hero placeholder
    case weekly      // 4:5, corner 16 — weekly portrait tile
    case ai          // 1:1, corner 16 — AI square tile
    case live        // 16:10, corner 10 — Live (MacDynamicTile) shape
    case collection  // 1:1, corner 14 — collection stacked-paper tile

    var aspectRatio: CGFloat {
        switch self {
        case .hero:       return 16.0 / 9.0
        case .weekly:     return 4.0 / 5.0
        case .ai:         return 1.0
        case .live:       return 16.0 / 10.0
        case .collection: return 1.0
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .hero:       return 24
        case .weekly:     return 16
        case .ai:         return 16
        case .live:       return 10
        case .collection: return 14
        }
    }
}

struct SkeletonTile: View {
    let variant: SkeletonVariant

    var body: some View {
        switch variant {
        case .collection:
            // Collection skeleton: mirror CollectionCard's paper-stack
            // layout so the layout footprint matches what's about to
            // land in its place (no jump on data arrival).
            GeometryReader { geom in
                let cell = min(geom.size.width, geom.size.height)
                let cardSize = max(0, cell - 12)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.81, green: 0.81, blue: 0.83))
                        .frame(width: cardSize, height: cardSize)
                        .offset(x: 8, y: 8)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.86, green: 0.86, blue: 0.87))
                        .frame(width: cardSize, height: cardSize)
                        .offset(x: 4, y: 4)
                    plate(cornerRadius: 14)
                        .frame(width: cardSize, height: cardSize)
                }
                .frame(width: cell, height: cell, alignment: .topLeading)
            }
            .aspectRatio(1.0, contentMode: .fit)

        default:
            plate(cornerRadius: variant.cornerRadius)
                .aspectRatio(variant.aspectRatio, contentMode: .fit)
        }
    }

    // Inner plate: paper-2 base + shimmer overlay + 1px top-inset white
    // highlight (matches .h3-tile's inset 0 1px 0 oklch(100% / 0.5)).
    @ViewBuilder
    private func plate(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.paper2)
            ShimmerBand()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

// ─── ShimmerBand ────────────────────────────────────────────────
// One repeating 100deg sweep — diagonal band that crosses the tile
// every 1.6s. SwiftUI's animation runs on the @State driver; we use
// `phase` ∈ [-1, 1] to translate the band from off-left to off-right.
struct ShimmerBand: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            // Band wider than the tile so the edges fade off-screen
            // smoothly. The translateX moves the band's center from
            // -w (off-left) to +w (off-right) ⇒ a (2 * w) sweep.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: Color.white.opacity(0.42), location: 0.50),
                    .init(color: .clear, location: 0.70),
                ],
                // 100deg gradient ≈ slight top-left to bottom-right
                // diagonal. UnitPoint(0.1, 0) → (0.9, 1) gives the
                // visual approximation web's 100deg produces.
                startPoint: UnitPoint(x: 0.1, y: 0),
                endPoint:   UnitPoint(x: 0.9, y: 1)
            )
            .frame(width: w * 1.6, height: h * 1.2)
            .offset(x: phase * w * 1.3)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
        }
    }
}
