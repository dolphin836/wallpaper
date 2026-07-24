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
            let contentWidth = max(1, proxy.size.width - 80)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Empty band at the top: the first screenful leads
                    // with the backdrop wallpaper itself.
                    Color.clear
                        .frame(height: max(280, proxy.size.height * 0.52))
                    content(availableWidth: contentWidth)
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

    private func content(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if failed {
                RemoteLoadErrorView(message: L10n.home.homeFeedError) {
                    Task { await load() }
                }
            } else {
                weeklySection(availableWidth: availableWidth)
            }
        }
        // Same margin logic as DiscoverView: a fixed 40pt gutter and a
        // full-width frame, so the grid keeps growing in full-screen
        // instead of pinning to a centered max width.
        .padding(.horizontal, 40)
        .padding(.bottom, 72)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─── Weekly picks ──────────────────────────────────────────

    private func weeklySection(availableWidth: CGFloat) -> some View {
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
                browseMoreLink
            } else if weeklyLoading {
                LazyVGrid(columns: gridCols, spacing: 28) {
                    ForEach(0..<weeklySkeletonCount(for: availableWidth), id: \.self) { _ in
                        HomeWeeklyCardSkeleton()
                    }
                }
            }
        }
    }

    // Just the big display title, drawn in white over the wallpaper
    // backdrop (the ink/accent pair belongs to the paper pages), one
    // uniform color, trailing full stop dropped.
    private var weeklyTitle: some View {
        Text(weeklyTitleString)
            .font(.system(size: 34, weight: .semibold, design: .serif))
            .foregroundColor(.white)
            .tracking(-0.3)
            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
    }

    private var weeklyTitleString: String {
        let full = L10n.home.weeklyTitleAccent + L10n.home.weeklyTitleRest
        return full.trimmingCharacters(in: CharacterSet(charactersIn: "。．. "))
    }

    // "Browse more" nav under the grid, bottom-trailing — routes to the
    // Discover page.
    private var browseMoreLink: some View {
        HStack {
            Spacer()
            Button(action: { onOpenDiscover(.latest) }) {
                Text(L10n.home.browseMore)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.45))
                            .frame(height: 1)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.top, 4)
    }

    // Adaptive columns, same approach as DiscoverView's grid: cards
    // have a comfortable min/max width and the grid fits as many per
    // row as the content area allows — ~3 in a 1280pt window, more in
    // full-screen, fewer when narrow.
    private var gridCols: [GridItem] {
        [GridItem(.adaptive(minimum: 330, maximum: 520), spacing: 28, alignment: .top)]
    }

    private func weeklySkeletonCount(for availableWidth: CGFloat) -> Int {
        let columns = max(1, Int(floor((availableWidth + 28) / (330 + 28))))
        return columns * 2
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
// on top of a split contact + ambient shadow, hover lifts the card.
// The CONTENT mirrors MainGridTile exactly — chips top-left
// (Resolution / Live / AI) and the hover action rail bottom-right
// (Favorite · Like · Download) — only the shell styling differs, so
// the browse pages' tile stays untouched.
private let goldenRatio: CGFloat = 1.618

struct HomeWeeklyCard: View {
    let wallpaper: Wallpaper
    @State private var hover = false
    @State private var manager = WallpaperManager.shared
    @State private var auth = AuthService.shared

    // Optimistic local mirrors, same pattern as MainGridTile: snappy
    // hover feedback here, authoritative state on the detail page.
    @State private var liked: Bool? = nil
    @State private var favorited: Bool? = nil
    @State private var downloaded: Bool? = nil
    @State private var busy: Bool = false

    private var isLiked: Bool { liked ?? (wallpaper.isLiked ?? false) }
    private var isFavorited: Bool { favorited ?? (wallpaper.isFavorited ?? false) }
    private var localFileExists: Bool { manager.isDownloaded(wallpaper.id) }
    private var isOwnWallpaper: Bool { auth.user?.id == wallpaper.userID }
    private var isDownloaded: Bool {
        if let downloaded { return downloaded }
        return wallpaper.isDownloaded ?? localFileExists
    }
    private var downloadHelp: String {
        if isDownloaded { return L10n.browse.tipGotIt }
        if isOwnWallpaper { return L10n.browse.tipDownload }
        return L10n.browse.tipTradeForOne
    }
    private var isTransferring: Bool { manager.downloading.contains(wallpaper.id) }
    private var downloadProgress: Double? { manager.downloadProgress[wallpaper.id] }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = w / goldenRatio
            ZStack {
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

                LinearGradient(
                    colors: [Color.black.opacity(0.20), .clear, .clear, Color.black.opacity(0.30)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(hover ? 1 : 0.65)
                .allowsHitTesting(false)

                // Chips top-left — same family as MainGridTile.
                VStack {
                    HStack(alignment: .top, spacing: 4) {
                        resolutionChip
                        if wallpaper.fileType.hasPrefix("video/") || wallpaper.isDynamic { liveChip }
                        if wallpaper.isAIGenerated == true { aiChip }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
                .allowsHitTesting(false)

                // Hover action rail bottom-right — Favorite · Like ·
                // Download, shared ActionDot component.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 5) {
                            ActionDot(icon: .system(isFavorited ? "star.fill" : "star"),
                                      kind: .favorite,
                                      active: isFavorited,
                                      help: isFavorited ? L10n.browse.tipUnfavorite : L10n.browse.tipFavorite,
                                      busy: busy,
                                      size: 24,
                                      action: { Task { await toggleFavorite() } })
                            ActionDot(icon: .system(isLiked ? "heart.fill" : "heart"),
                                      kind: .like,
                                      active: isLiked,
                                      help: isLiked ? L10n.browse.tipUnlike : L10n.browse.tipLike,
                                      busy: busy,
                                      size: 24,
                                      action: { Task { await toggleLike() } })
                            ActionDot(icon: isDownloaded ? .system("checkmark.circle") : .webDownload,
                                      kind: .download,
                                      active: isDownloaded,
                                      help: downloadHelp,
                                      busy: busy,
                                      loading: isTransferring,
                                      progress: downloadProgress,
                                      size: 24,
                                      action: { Task { await doDownload() } })
                        }
                        .opacity(hover ? 1 : 0)
                        .offset(y: hover ? 0 : 4)
                        .animation(.easeOut(duration: 0.2), value: hover)
                        .allowsHitTesting(hover)
                    }
                }
                .padding(12)
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

    // ─── Chips — same tokens as MainGridTile's .tile-chip family ──

    private static let chipBG   = Color.chipSurface
    private static let chipInk  = Color.chipInk
    private static let chipFont = Font.system(size: 9, weight: .semibold, design: .monospaced)

    private var resolutionChip: some View {
        Text(wallpaper.resolutionLabel)
            .font(Self.chipFont).tracking(0.4)
            .foregroundStyle(Self.chipInk)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Self.chipBG))
    }

    private var liveChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill").font(.system(size: 8, weight: .semibold))
            Text(L10n.browse.chipLive).font(Self.chipFont).tracking(0.4)
        }
        .foregroundStyle(Self.chipInk)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Self.chipBG))
    }

    private var aiChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .semibold))
            Text("AI").font(Self.chipFont).tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color.chipAI.opacity(0.85)))
    }

    // ─── Action handlers — same behavior as MainGridTile ──────────

    private func toggleLike() async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isLiked
        liked = !prev
        do {
            if prev { try await APIClient.shared.unlike(wallpaperID: wallpaper.id) }
            else    { try await APIClient.shared.like(wallpaperID: wallpaper.id) }
        } catch { liked = prev }
    }

    private func toggleFavorite() async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isFavorited
        favorited = !prev
        do {
            if prev { try await APIClient.shared.unfavorite(wallpaperID: wallpaper.id) }
            else    { try await APIClient.shared.favorite(wallpaperID: wallpaper.id) }
        } catch { favorited = prev }
    }

    private func doDownload() async {
        guard auth.isLoggedIn else { auth.login(); return }
        if localFileExists { return }
        busy = true
        defer { busy = false }
        do {
            try await manager.download(wallpaper: wallpaper)
            downloaded = true
            await auth.refreshProfile()
        } catch {}
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
