import SwiftUI

// Shared skeleton placeholders for remote-loading surfaces. The original
// tiles mirror the web's <SkeletonTile variant="..."/> from HomePage.tsx
// + the .skeleton-card shimmer in index.css.
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

struct SkeletonPlate: View {
    var aspectRatio: CGFloat = 3.0 / 2.0
    var cornerRadius: CGFloat = 10
    var shadow: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.paper2)
            ShimmerBand()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            ImageLoadingBeam(style: .skeleton)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .shadow(color: Color.black.opacity(shadow ? 0.10 : 0), radius: 8, x: 0, y: 4)
    }
}

struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 10
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.paper2)
            .frame(width: width, height: height)
            .overlay { ShimmerBand().clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)) }
    }
}

struct WallpaperGridSkeleton: View {
    let columns: [GridItem]
    var count: Int = 12
    var spacing: CGFloat = 14
    var aspectRatio: CGFloat = 3.0 / 2.0
    var cornerRadius: CGFloat = 10

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonPlate(aspectRatio: aspectRatio, cornerRadius: cornerRadius)
            }
        }
    }
}

struct CollectionGridSkeleton: View {
    let columns: [GridItem]
    var count: Int = 8
    var spacing: CGFloat = 24

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonTile(variant: .collection)
                    SkeletonLine(width: 86, height: 8)
                    SkeletonLine(width: 150, height: 18)
                    SkeletonLine(width: 102, height: 8)
                }
            }
        }
    }
}

struct CardListSkeleton: View {
    var rows: Int = 4
    var thumbSize: CGSize = CGSize(width: 56, height: 56)
    var rowHeight: CGFloat = 112

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(alignment: .top, spacing: 14) {
                    SkeletonPlate(aspectRatio: thumbSize.width / max(thumbSize.height, 1), cornerRadius: min(thumbSize.width, thumbSize.height) / 2)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonLine(width: 160, height: 16)
                        SkeletonLine(width: 100, height: 9)
                        SkeletonLine(width: 230, height: 9)
                        HStack(spacing: 14) {
                            SkeletonLine(width: 68, height: 20)
                            SkeletonLine(width: 82, height: 20)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonPlate(aspectRatio: 38.0 / 26.0, cornerRadius: 6, shadow: false)
                                .frame(width: 38, height: 26)
                        }
                    }
                }
                .padding(14)
                .frame(minHeight: rowHeight, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.paper.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hair, lineWidth: 1))
            }
        }
    }
}

struct ProfileHeaderSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            SkeletonPlate(aspectRatio: 1, cornerRadius: 48)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 10) {
                SkeletonLine(width: 180, height: 10)
                SkeletonLine(width: 240, height: 30)
                SkeletonLine(width: 420, height: 12)
                HStack(spacing: 24) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonLine(width: 72, height: 8)
                            SkeletonLine(width: 42, height: 22)
                        }
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
    }
}

struct LedgerRowsSkeleton: View {
    var rows: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 14) {
                    SkeletonPlate(aspectRatio: 1, cornerRadius: 14, shadow: false)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonLine(width: 220, height: 12)
                        SkeletonLine(width: 96, height: 8)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        SkeletonLine(width: 42, height: 14)
                        SkeletonLine(width: 58, height: 8)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hair.opacity(0.6)).frame(height: 0.5).padding(.horizontal, 18)
                }
            }
        }
    }
}

struct RemoteLoadErrorView: View {
    // Default-argument expressions re-evaluate at each call site, so the
    // localized defaults track language switches across the .id() remount.
    var title: String = L10n.browse.errorTitle
    var message: String
    var retryTitle: String = L10n.common.retry
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.warn.opacity(0.12))
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.warn)
            }
            .frame(width: 44, height: 44)
            Text(title)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.system(size: 12))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 420)
            if let retry = retry {
                Button(action: retry) {
                    Text(retryTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.paper2))
                        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

struct RemoteEmptyStateView: View {
    var title: String
    var message: String
    var symbol: String = "photo.on.rectangle"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.paper2.opacity(0.78))
                Circle().stroke(Color.hair, lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
            .frame(width: 44, height: 44)

            Text(title)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 12))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 420)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
                        .fill(Color.paper3)
                        .frame(width: cardSize, height: cardSize)
                        .offset(x: 8, y: 8)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.paper2)
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
            ImageLoadingBeam(style: .skeleton)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    var body: some View {
        Group {
            if reduceMotion {
                Color.clear
            } else {
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
                        phase = -1.0
                        withAnimation(
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: false)
                        ) {
                            phase = 1.0
                        }
                    }
                }
            }
        }
    }
}
