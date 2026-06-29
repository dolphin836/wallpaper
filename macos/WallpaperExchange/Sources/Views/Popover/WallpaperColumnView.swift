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
    // Optional folder-open action — only Downloaded column gets one,
    // since Latest has no local-file concept.
    let onOpenLocalFolder: (() -> Void)?

    let emptyTitle: String
    let emptySubtitle: String?

    let onDownload: (Wallpaper) -> Void
    let onRedownload: (Wallpaper) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if shuffleOn {
                ShuffleStatusBanner(nextAt: shuffleNextAt, intervalText: manager.autoRotateIntervalLabel)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if wallpapers.isEmpty && isLoading {
                        // Skeleton placeholder tiles — same 16:10 chrome,
                        // paper-2 fill, no image. Layout stays stable when
                        // the real tiles arrive.
                        ForEach(0..<4, id: \.self) { _ in skeletonTile }
                    } else {
                        ForEach(Array(wallpapers.enumerated()), id: \.element.id) { idx, wp in
                            WallpaperTileView(
                                wallpaper: wp,
                                kind: kind,
                                isDownloading: manager.downloading.contains(wp.id),
                                downloadProgress: manager.downloadProgress[wp.id],
                                localFileExists: manager.downloadedIDs.contains(wp.id),
                                isActive: manager.currentWallpaperID == wp.id,
                                onDownload: { onDownload(wp) },
                                onRedownload: { onRedownload(wp) }
                            )
                            .onAppear {
                                // Pre-fetch the next page once the user has
                                // scrolled within three tiles of the end.
                                // Three is enough lead time that on a normal
                                // network the next batch is already there by
                                // the time they hit the actual bottom — the
                                // visible loading indicator below only ever
                                // appears on slow networks.
                                if hasMore, !isLoading, idx >= wallpapers.count - 3 {
                                    onLoadMore()
                                }
                            }
                        }

                        listFooter
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
                            ? L10n.manager.autoShuffleTooltipOn
                            : L10n.manager.autoShuffleTooltipOff(manager.autoRotateIntervalLabel),
                        isOn: shuffleOn,
                        action: onShuffleToggle
                    )
                }
                FilterTogglePill(
                    icon: "apple.logo",
                    help: macOnly
                        ? L10n.manager.macDynamicShowingOnly
                        : L10n.manager.macDynamicShowOnly,
                    isOn: macOnly,
                    action: onMacOnlyToggle
                )
                if let onOpenLocalFolder {
                    FilterTogglePill(
                        icon: "folder",
                        help: L10n.manager.revealDownloadsFolder,
                        isOn: false,
                        action: onOpenLocalFolder
                    )
                }
                // Loading indicator lives in `listFooter` (bottom of the
                // scroll view) instead of here — placing it in this HStack
                // made the filter toggles jump leftward whenever a fetch
                // kicked off, then snap back when it completed.
            }
        }
    }

    private var skeletonTile: some View {
        SkeletonPlate(aspectRatio: 16.0 / 10.0, cornerRadius: 8, shadow: false)
    }

    // Tri-state footer sitting under the last tile. Order matters:
    //   - If we're actively fetching a follow-on page, show the spinner.
    //     This only appears when the prefetch in .onAppear couldn't keep
    //     up with the user's scroll speed; on normal networks the next
    //     page is already in `wallpapers` by the time the user reaches
    //     the bottom and the spinner is skipped entirely.
    //   - Otherwise, if there's still more to load, render the manual
    //     "Load more" affordance as a fallback (also lets the user
    //     re-trigger after a network failure).
    //   - Once the server reports has_more=false we draw a hairline-
    //     flanked "End" mark so the user knows the list is exhausted
    //     rather than wondering if it failed to load.
    @ViewBuilder private var listFooter: some View {
        if isLoading && !wallpapers.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading more…")
                    .font(.sans11)
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if hasMore {
            Button(action: onLoadMore) {
                Text("Load more")
                    .font(.sans11)
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if !wallpapers.isEmpty {
            HStack(spacing: 10) {
                Rectangle().fill(Color.hair).frame(width: 32, height: 1)
                Text("End")
                    .font(.monoCaps)
                    .tracking(1.4)
                    .foregroundStyle(Color.muted)
                Rectangle().fill(Color.hair).frame(width: 32, height: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
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
