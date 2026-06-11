import SwiftUI

// Two-column masonry-ish grid shared by every wallpaper list surface.
// Tiles keep each wallpaper's aspect ratio (clamped so extreme panoramas
// don't collapse a row) and navigate to the detail page by slug.
struct WallpaperGrid: View {
    let wallpapers: [Wallpaper]
    var hasMore: Bool = false
    var onLoadMore: (() -> Void)? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(wallpapers) { wallpaper in
                NavigationLink(value: WallpaperRoute(slug: wallpaper.slug)) {
                    WallpaperTile(wallpaper: wallpaper)
                }
                .buttonStyle(.plain)
            }
            if hasMore, let onLoadMore {
                // Sentinel tile — appearing means the user reached the
                // grid's tail, so pull the next page.
                Color.clear
                    .frame(height: 1)
                    .onAppear { onLoadMore() }
            }
        }
        .padding(.horizontal, 12)
    }
}

// Navigation payload: detail pages load by slug (the sharable key the
// web uses), so any surface can deep-link with just a slug.
struct WallpaperRoute: Hashable {
    let slug: String
}

struct WallpaperTile: View {
    let wallpaper: Wallpaper

    private var aspectRatio: CGFloat {
        guard wallpaper.width > 0, wallpaper.height > 0 else { return 0.7 }
        let ratio = CGFloat(wallpaper.width) / CGFloat(wallpaper.height)
        return min(max(ratio, 0.55), 1.8)
    }

    var body: some View {
        CachedAsyncImage(url: URL(string: wallpaper.displayURL), maxPixelDimension: 700) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color(hex: wallpaper.dominantColor) ?? Color.shimGray5)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                chip(wallpaper.resolutionLabel)
                if wallpaper.isAIGenerated == true {
                    chip("AI", tint: .purple)
                }
                if wallpaper.isDynamic {
                    chip("LIVE", tint: .orange)
                }
            }
            .padding(6)
        }
    }

    private func chip(_ text: String, tint: Color = .black) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.55), in: Capsule())
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
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
