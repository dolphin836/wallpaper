import SwiftUI

// Two-column masonry grid shared by every wallpaper list surface.
// True masonry (each column stacks independently, items assigned to the
// currently-shorter column) — LazyVGrid aligns rows, so one tall
// portrait tile next to a panorama left a hole under the short one.
struct WallpaperGrid: View {
    let wallpapers: [Wallpaper]
    var hasMore: Bool = false
    var isLoading: Bool = false
    var showsEndState: Bool = true
    var onLoadMore: (() -> Void)? = nil

    private var columns: (left: [Wallpaper], right: [Wallpaper]) {
        // Every tile renders at the device screen ratio, so the columns
        // stay balanced with a plain alternating split.
        var left: [Wallpaper] = []
        var right: [Wallpaper] = []
        for (i, wallpaper) in wallpapers.enumerated() {
            if i.isMultiple(of: 2) {
                left.append(wallpaper)
            } else {
                right.append(wallpaper)
            }
        }
        return (left, right)
    }

    var body: some View {
        let split = columns
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                column(split.left)
                column(split.right)
            }
            .padding(.horizontal, 14)

            PagingFooter(
                isLoading: isLoading,
                hasMore: hasMore,
                showsEndState: showsEndState,
                onLoadMore: onLoadMore
            )
        }
    }

    private func column(_ items: [Wallpaper]) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(items) { wallpaper in
                WallpaperDetailLauncher(route: WallpaperRoute(slug: wallpaper.slug, initialWallpaper: wallpaper)) {
                    WallpaperTile(wallpaper: wallpaper)
                }
            }
        }
    }
}

// Navigation payload: detail pages load by slug (the sharable key the
// web uses), so any surface can deep-link with just a slug.
struct WallpaperRoute: Hashable {
    let slug: String
    let initialWallpaper: Wallpaper?

    init(slug: String, initialWallpaper: Wallpaper? = nil) {
        self.slug = slug
        self.initialWallpaper = initialWallpaper
    }
}

@MainActor
@Observable
final class WallpaperDetailRouter {
    static let shared = WallpaperDetailRouter()

    var route: WallpaperRoute?

    private init() {}

    func present(_ route: WallpaperRoute) {
        self.route = route
    }

    func dismiss() {
        route = nil
    }
}

struct WallpaperDetailLauncher<Label: View>: View {
    let route: WallpaperRoute
    let label: () -> Label

    @Environment(WallpaperDetailRouter.self) private var detailRouter

    init(route: WallpaperRoute, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.label = label
    }

    var body: some View {
        Button {
            detailRouter.present(route)
        } label: {
            label()
        }
        .buttonStyle(.pressable)
    }
}

struct WallpaperTile: View {
    let wallpaper: Wallpaper

    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        // Every tile previews at the device's screen ratio with a
        // centered .fill crop — what the image will actually look like
        // set as this device's wallpaper. Reserving the cell with
        // Color.clear keeps extreme intrinsic ratios (32:9 ultra-wides)
        // from blowing the cell out of its column.
        Color.clear
            .aspectRatio(DeviceScreenRatio.value, contentMode: .fit)
            .overlay(
                ProgressiveWallpaperImage(wallpaper: wallpaper)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
            // Hairline frame keeps very light/very dark images from
            // dissolving into the paper background.
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.hair.opacity(0.58), lineWidth: 1)
        )
        .overlay {
            if prefs.lockPreview {
                LockScreenOverlay(compact: true)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            // Chips yield to the lock mock — the clock occupies the same
            // band, and the point of the mode is judging the image.
            if !prefs.lockPreview {
                HStack(spacing: 4) {
                    MediaChip(text: wallpaper.resolutionLabel)
                    if wallpaper.isAIGenerated == true {
                        MediaChip(text: "AI", tint: Color.accent.opacity(0.78))
                    }
                    if wallpaper.isDownloaded == true {
                        MediaChip(text: L10n.strings(for: prefs.language).downloadedChip, tint: Color.accentInk.opacity(0.72))
                    }
                }
                .padding(7)
            }
        }
        // Tinted lift: each tile throws a soft shadow in its own
        // dominant color, so the grid reads as prints on paper rather
        // than rectangles on a flat fill.
        .shadow(
            color: (Color(hex: wallpaper.dominantColor) ?? .black).opacity(0.18),
            radius: 12, y: 6
        )
        .paletteReactive(palette: wallpaper.colorPalette, dominant: wallpaper.dominantColor)
        .archiveScrollLift()
        .accessibilityLabel("\(wallpaper.title), \(wallpaper.resolutionLabel)")
    }
}

private struct ProgressiveWallpaperImage: View {
    let wallpaper: Wallpaper

    @State private var lowLoaded = false
    @State private var highLoaded = false
    @State private var shouldLoadHigh = false
    @State private var lowFailed = false
    @State private var highFailed = false

    private var lowURL: URL? {
        let thumb = wallpaper.thumbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let high = wallpaper.displayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thumb.isEmpty, thumb != high else { return nil }
        return URL(string: thumb)
    }

    private var highURL: URL? {
        let value = wallpaper.displayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private var dominantFill: Color {
        Color(hex: wallpaper.dominantColor) ?? Color.paper3
    }

    private var lowIsCached: Bool {
        guard let lowURL else { return false }
        return ImageCacheStore.shared.get(lowURL, maxPixelDimension: 360) != nil
    }

    private var highIsCached: Bool {
        guard let highURL else { return false }
        return ImageCacheStore.shared.get(highURL, maxPixelDimension: 1400) != nil
    }

    private var showsLoadingVeil: Bool {
        if highLoaded || highFailed || highIsCached { return false }
        if highURL != nil { return true }
        return lowURL != nil && !lowLoaded && !lowFailed && !lowIsCached
    }

    var body: some View {
        ZStack {
            Rectangle().fill(dominantFill)

            if let lowURL {
                CachedAsyncImage(
                    url: lowURL,
                    maxPixelDimension: 360,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.22)) {
                            lowLoaded = true
                            shouldLoadHigh = true
                        }
                    },
                    onFailure: {
                        lowFailed = true
                        shouldLoadHigh = true
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: highLoaded ? 0 : 9)
                        .saturation(highLoaded ? 1 : 1.16)
                        .scaleEffect(highLoaded ? 1 : 1.08)
                        .opacity(highLoaded || highIsCached ? 0 : 0.92)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if shouldLoadHigh || lowURL == nil || highIsCached {
                // 1400px decode budget: a half-width tile at the device
                // ratio is ~1206 physical px tall on a 3x phone, so the
                // source preview usually has enough pixels without using
                // the original image.
                CachedAsyncImage(
                    url: highURL,
                    maxPixelDimension: 1400,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            highLoaded = true
                        }
                    },
                    onFailure: {
                        highFailed = true
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if showsLoadingVeil {
                ImageLoadingVeil(strength: lowLoaded ? .whisper : .card)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: wallpaper.id) {
            lowLoaded = false
            highLoaded = false
            lowFailed = false
            highFailed = false
            shouldLoadHigh = lowURL == nil || highIsCached
            if lowURL != nil {
                try? await Task.sleep(nanoseconds: 850_000_000)
                guard !Task.isCancelled else { return }
                // If the tiny thumb is unavailable or slow, still let the
                // preview load. Dominant color remains the fallback.
                shouldLoadHigh = true
            }
        }
    }
}

extension Color {
    // Parses "#aabbcc" / "aabbcc"; nil for anything else.
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// Shared inline states used by every paged list screen.
struct LoadingFooter: View {
    @Environment(UIPrefs.self) private var prefs
    @State private var glow = false

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(L10n.strings(for: prefs.language).loadingMore)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.muted)
            Spacer()
        }
        .opacity(glow ? 1 : 0.62)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
        .padding(.vertical, 16)
    }
}

struct PagingFooter: View {
    let isLoading: Bool
    let hasMore: Bool
    var showsEndState = true
    let onLoadMore: (() -> Void)?

    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        Group {
            if isLoading {
                LoadingFooter()
            } else if hasMore, let onLoadMore {
                Button(action: onLoadMore) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text(s.loadMore)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentInk)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Color.paper2.opacity(0.76), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hair.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                // Keep infinite scroll, but leave a visible manual affordance
                // when the sentinel does not fire in a simulator or slow list.
                .onAppear { onLoadMore() }
            } else if showsEndState {
                Kicker(text: s.allLoaded)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
    }
}

struct ErrorRetryView: View {
    let message: String
    let retry: () -> Void

    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        VStack(spacing: 10) {
            Kicker(text: s.connectionLost, tint: .warn)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(s.retry)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Color.paper2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// Section heading: bold title with a quiet supporting line below —
// the reference's shelf-header pairing.
struct SectionHeader: View {
    var kicker: String? = nil
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.ink)
            if let kicker, !kicker.isEmpty {
                Text(kicker)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
        }
    }
}
