import SwiftUI

// One column of the two-column popover body. Shared chrome — heading row
// with editorial typography + filter pills, optional shuffle banner,
// scrolling tile list — driven by which actions to render on hover via
// `kind`.
struct WallpaperColumnView: View {
    let title: String
    let icon: String                // SF Symbol for the heading
    let wallpapers: [Wallpaper]
    let isLoading: Bool
    let hasMore: Bool
    let kind: WallpaperTileKind
    let manager: WallpaperManager

    // Toggles
    let macOnly: Bool
    let onMacOnlyToggle: () -> Void
    let shuffleOn: Bool
    let hasShuffle: Bool
    let onShuffleToggle: (() -> Void)?
    let shuffleNextAt: Date?

    let emptyTitle: String
    let emptySubtitle: String?

    let onDownload: (Wallpaper) -> Void
    let onDownloadAndSet: (Wallpaper) -> Void
    let onSetWallpaper: (Wallpaper) -> Void
    let onRedownload: (Wallpaper) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if shuffleOn {
                ShuffleStatusBanner(nextAt: shuffleNextAt)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if wallpapers.isEmpty && isLoading {
                        // Skeleton placeholder tiles — same 16:10 chrome,
                        // paper-2 fill, no image. Layout stays stable when
                        // the real tiles arrive.
                        ForEach(0..<3, id: \.self) { _ in skeletonTile }
                    } else {
                        ForEach(wallpapers) { wp in
                            WallpaperTileView(
                                wallpaper: wp,
                                kind: kind,
                                isDownloading: manager.downloading.contains(wp.id),
                                downloadProgress: manager.downloadProgress[wp.id],
                                localFileExists: manager.downloadedIDs.contains(wp.id),
                                isActive: manager.currentWallpaperID == wp.id,
                                onDownload: { onDownload(wp) },
                                onDownloadAndSet: { onDownloadAndSet(wp) },
                                onSetWallpaper: { onSetWallpaper(wp) },
                                onRedownload: { onRedownload(wp) }
                            )
                        }
                    }

                    if hasMore {
                        Button(action: onLoadMore) {
                            Text("Load more")
                                .font(.sans11)
                                .foregroundStyle(Color.muted)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                    }

                    if !isLoading && wallpapers.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    // ─── Sub-views ─────────────────────────────────────────────────

    private var heading: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.ink)
                Text(title)
                    .font(.displayLg)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            HStack(spacing: 6) {
                if hasShuffle, let onShuffleToggle {
                    FilterTogglePill(
                        icon: "shuffle",
                        help: shuffleOn
                            ? "Auto-shuffle on — click to stop"
                            : "Auto-shuffle every 4 hours",
                        isOn: shuffleOn,
                        action: onShuffleToggle
                    )
                }
                FilterTogglePill(
                    icon: "apple.logo",
                    help: macOnly
                        ? "Showing only macOS dynamic wallpapers"
                        : "Show only macOS dynamic wallpapers",
                    isOn: macOnly,
                    action: onMacOnlyToggle
                )
                if isLoading && !wallpapers.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private var skeletonTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.paper2)
            .aspectRatio(16.0/10.0, contentMode: .fit)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: kind == .downloaded ? "tray" : "photo.on.rectangle.angled")
                .font(.system(size: 22))
                .foregroundStyle(Color.muted.opacity(0.6))
            Text(emptyTitle)
                .font(.displayMd)
                .foregroundStyle(Color.ink2)
            if let emptySubtitle {
                Text(emptySubtitle)
                    .font(.sans12)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
