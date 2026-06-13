import SwiftUI

// Two-column masonry grid shared by every wallpaper list surface.
// True masonry (each column stacks independently, items assigned to the
// currently-shorter column) — LazyVGrid aligns rows, so one tall
// portrait tile next to a panorama left a hole under the short one.
struct WallpaperGrid: View {
    let wallpapers: [Wallpaper]
    var hasMore: Bool = false
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
        HStack(alignment: .top, spacing: 14) {
            column(split.left)
            column(split.right)
        }
        .padding(.horizontal, 14)
        if hasMore, let onLoadMore {
            // Sentinel below both columns — appearing means the user
            // reached the grid's tail, so pull the next page.
            Color.clear
                .frame(height: 1)
                .onAppear { onLoadMore() }
        }
    }

    private func column(_ items: [Wallpaper]) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(items) { wallpaper in
                NavigationLink(value: WallpaperRoute(slug: wallpaper.slug)) {
                    WallpaperTile(wallpaper: wallpaper)
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

// Navigation payload: detail pages load by slug (the sharable key the
// web uses), so any surface can deep-link with just a slug.
struct WallpaperRoute: Hashable {
    let slug: String
}

struct WallpaperTile: View {
    let wallpaper: Wallpaper

    @Environment(UIPrefs.self) private var prefs
    @State private var imageLoaded = false

    var body: some View {
        // Every tile previews at the device's screen ratio with a
        // centered .fill crop — what the image will actually look like
        // set as this device's wallpaper. Reserving the cell with
        // Color.clear keeps extreme intrinsic ratios (32:9 ultra-wides)
        // from blowing the cell out of its column.
        Color.clear
            .aspectRatio(DeviceScreenRatio.value, contentMode: .fit)
            .overlay(
                // 1400px decode budget: a half-width tile at the device
                // ratio is ~1206 physical px tall on a 3x phone, so the
                // old 700px budget upscaled every tile ~2x — the source
                // preview (1600w) usually has the pixels, use them.
                CachedAsyncImage(
                    url: URL(string: wallpaper.displayURL),
                    maxPixelDimension: 1400,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            imageLoaded = true
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(imageLoaded ? 1 : 1.025)
                        .opacity(imageLoaded ? 1 : 0)
                } placeholder: {
                    Rectangle()
                        .fill(Color(hex: wallpaper.dominantColor) ?? Color.paper3)
                }
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
                        MediaChip(text: "Saved", tint: Color.accentInk.opacity(0.72))
                    }
                }
                .padding(7)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !prefs.lockPreview {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.lightText)
                        .lineLimit(1)
                    Text(tileMeta)
                        .font(.mono10)
                        .tracking(0.4)
                        .foregroundStyle(Color.lightText.opacity(0.68))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
                .padding(.top, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.10), .black.opacity(0.58)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        // Tinted lift: each tile throws a soft shadow in its own
        // dominant color, so the grid reads as prints on paper rather
        // than rectangles on a flat fill.
        .shadow(
            color: (Color(hex: wallpaper.dominantColor) ?? .black).opacity(0.18),
            radius: 12, y: 6
        )
        .archiveScrollLift()
        .onChange(of: wallpaper.id) { _, _ in imageLoaded = false }
        .accessibilityLabel("\(wallpaper.title), \(wallpaper.resolutionLabel)")
    }

    private var tileMeta: String {
        if wallpaper.downloadCount > 0 {
            return "\(compactCount(wallpaper.downloadCount)) downloads"
        }
        if wallpaper.likeCount > 0 {
            return "\(compactCount(wallpaper.likeCount)) likes"
        }
        if wallpaper.isAIGenerated == true {
            return "AI wallpaper"
        }
        return "Wallpaper"
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return "\(value / 1_000)k"
        }
        if value >= 1_000 {
            let scaled = Double(value) / 1_000
            return String(format: "%.1fk", scaled)
        }
        return "\(value)"
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
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

struct ErrorRetryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Kicker(text: "Connection lost", tint: .warn)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Retry")
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
    var kicker: String
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.ink)
            Text(kicker)
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
    }
}
