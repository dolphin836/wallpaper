import SwiftUI

// Immersive home page:
//   • The weekly hero pick is the page BACKGROUND — published to
//     HomeBackdropEnv and rendered full-window by MainWindow with the
//     detail-page loading order (default mesh → dominant → thumb →
//     original).
//   • A transparent band at the top lets the backdrop breathe.
//   • One content row: this week's picks, on home-only landscape cards
//     (golden ratio) with generous spacing.
struct HomeView: View {
    var onPick: (Wallpaper) -> Void
    var onOpenWeek: (Int, Int) -> Void
    // Retained for the ContentRouter call site; the home page currently
    // surfaces only the weekly slate.
    var onOpenDiscover: (DiscoverView.Filter) -> Void = { _ in }
    var onOpenCollections: () -> Void = {}
    var onOpenWeeklyArchive: () -> Void = {}
    var onCollection: (CollectionItem) -> Void = { _ in }

    @State private var weekly: WeeklyCurrent?
    @State private var weeklyLoading = true
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Empty band at the top: the first screenful leads
                    // with the backdrop wallpaper itself.
                    Color.clear
                        .frame(height: max(280, proxy.size.height * 0.52))
                    content
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .task { await load() }
    }

    private var heroPick: WeeklyPicked? {
        weekly?.picks.first(where: { $0.isHero }) ?? weekly?.picks.first
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if failed {
                RemoteLoadErrorView(message: L10n.home.homeFeedError) {
                    Task { await load() }
                }
            } else {
                weeklySection
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 72)
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // ─── Weekly picks ──────────────────────────────────────────

    private var weeklySection: some View {
        let picks = weekly?.picks ?? []
        return VStack(alignment: .leading, spacing: 28) {
            weeklyTitle
            if !picks.isEmpty {
                LazyVGrid(columns: gridCols, spacing: 28) {
                    ForEach(picks) { p in
                        let wp = weeklyToWallpaper(p)
                        Button(action: { onPick(wp) }) {
                            HomeWeeklyCard(wallpaper: wp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if weeklyLoading {
                LazyVGrid(columns: gridCols, spacing: 28) {
                    ForEach(0..<6, id: \.self) { _ in
                        HomeWeeklyCardSkeleton()
                    }
                }
            }
        }
    }

    // Just the big display title, drawn in white over the wallpaper
    // backdrop (the ink/accent pair belongs to the paper pages). The
    // accent word keeps its weight for rhythm, the rest sits slightly
    // dimmer.
    private var weeklyTitle: some View {
        (
            Text(L10n.home.weeklyTitleAccent)
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundColor(.white)
            +
            Text(L10n.home.weeklyTitleRest)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundColor(.white.opacity(0.82))
        )
        .tracking(-0.3)
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
    }

    private var gridCols: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 3)
    }

    private func load() async {
        weeklyLoading = true
        failed = false

        let w = try? await APIClient.shared.fetchWeeklyCurrent()
        weekly = w
        weeklyLoading = false
        failed = w == nil
        publishBackdrop()
    }

    // Push the hero pick into the shared backdrop env so MainWindow can
    // paint it behind the whole window. Original falls back to preview
    // (same rule the old HeroCard used for its high-res source).
    private func publishBackdrop() {
        guard let hero = heroPick else { return }
        let original = hero.originalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        HomeBackdropEnv.shared.set(
            dominant: hero.dominantColor,
            thumb: hero.thumbURL,
            original: original.isEmpty ? hero.previewURL : original
        )
    }

    private func weeklyToWallpaper(_ p: WeeklyPicked) -> Wallpaper {
        Wallpaper(
            id: p.id, slug: p.slug, userID: 0, categoryID: nil, title: p.title, description: "",
            originalURL: p.originalURL, thumbURL: p.thumbURL, previewURL: p.previewURL,
            width: p.width, height: p.height, fileSize: p.fileSize, fileType: p.fileType,
            dominantColor: p.dominantColor, colorPalette: p.colorPalette, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: p.isDynamic,
            isAIGenerated: p.isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}

// Home-only weekly card. Landscape, golden ratio (φ ≈ 1.618:1), large
// corner radius, floating over the photo backdrop: a bright hairline
// on top of a split contact + ambient shadow, hover lifts the card and
// reveals the title on a bottom scrim. Deliberately separate from
// MainGridTile — the browse pages keep their own tile.
private let goldenRatio: CGFloat = 1.618

struct HomeWeeklyCard: View {
    let wallpaper: Wallpaper
    @State private var hover = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = w / goldenRatio
            ZStack(alignment: .bottomLeading) {
                Color(hex: wallpaper.dominantColor ?? "#999").opacity(0.45)

                ProgressiveCachedAsyncImage(
                    lowURL: URL(string: wallpaper.thumbURL),
                    highURL: URL(string: wallpaper.previewURL.isEmpty ? wallpaper.thumbURL : wallpaper.previewURL),
                    lowMaxPixelDimension: 560,
                    highMaxPixelDimension: 1200
                ) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(width: w, height: h)
                .clipped()

                // Bottom scrim + title, revealed on hover.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center, endPoint: .bottom
                )
                .opacity(hover ? 1 : 0)
                .allowsHitTesting(false)

                if !wallpaper.title.isEmpty {
                    Text(wallpaper.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 13)
                        .opacity(hover ? 1 : 0)
                        .offset(y: hover ? 0 : 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(hover ? 0.55 : 0.35), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
        }
        .aspectRatio(goldenRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.20), radius: 3, y: 2)
        .shadow(color: .black.opacity(hover ? 0.34 : 0.22), radius: hover ? 22 : 14, y: hover ? 12 : 7)
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: hover)
        .onHover { entered in
            hover = entered
            if entered {
                PaletteEnv.shared.apply(palette: wallpaper.colorPalette, dominant: wallpaper.dominantColor)
            } else {
                PaletteEnv.shared.resetToDefaults()
            }
        }
        .contentShape(Rectangle())
    }
}

// Loading placeholder matching HomeWeeklyCard's exact silhouette.
struct HomeWeeklyCardSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(
                ImageLoadingBeam(style: .skeleton)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .aspectRatio(goldenRatio, contentMode: .fit)
    }
}
