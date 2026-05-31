import SwiftUI

// Home page layout matches the web's HomePage:
//   1. Hero card (big featured pick from /weekly-picks/current,
//      tinted by its palette).
//   2. This week's picks rest of slate — 5-column grid.
//   3. Mac Dynamic — 4-column grid using the new MacDynamicTile
//      that hints at the multi-frame nature of these wallpapers.
//   4. AI Lab — 5-column grid.
//   5. Themed collections — 4-column rail.
struct HomeView: View {
    var onPick: (Wallpaper) -> Void
    var onOpenWeek: (Int, Int) -> Void

    @State private var weekly: WeeklyCurrent?
    @State private var dynamicWalls: [Wallpaper] = []
    @State private var aiWalls: [Wallpaper] = []
    @State private var collections: [CollectionItem] = []
    @State private var loading = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                if let hero = weekly?.picks.first(where: { $0.isHero }) ?? weekly?.picks.first {
                    HeroCard(pick: hero, week: weekly!.week, year: weekly!.year, onTap: { onPick(weeklyToWallpaper(hero)) })
                }
                weeklySection
                macDynamicSection
                aiSection
                collectionsSection
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await loadAll() }
    }

    // ─── Sections ──────────────────────────────────────────────

    private var weeklySection: some View {
        let restPicks = (weekly?.picks ?? []).filter { p in p.id != heroID } .prefix(5)
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: weekly.map { "Curation · Week \($0.week)" } ?? "Curated each Friday",
                title: "This week's picks.",
                ctaLabel: "View archive →",
                ctaEnabled: weekly != nil,
                onCTA: { if let w = weekly { onOpenWeek(w.year, w.week) } }
            )
            if !restPicks.isEmpty {
                LazyVGrid(columns: fixedCols(5), spacing: 16) {
                    ForEach(restPicks) { p in
                        let wp = weeklyToWallpaper(p)
                        Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                            .buttonStyle(.plain)
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var macDynamicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "Multi-frame · solar / h24 / apr",
                title: "Mac Dynamic Wallpapers.",
                ctaLabel: "All dynamic →",
                ctaEnabled: true
            )
            if dynamicWalls.isEmpty {
                placeholder
            } else {
                LazyVGrid(columns: fixedCols(4), spacing: 14) {
                    ForEach(dynamicWalls.prefix(8)) { wp in
                        Button(action: { onPick(wp) }) { MacDynamicTile(wallpaper: wp) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "AI Lab · synthetic samples",
                title: "Generated this week.",
                ctaLabel: "All AI →",
                ctaEnabled: true
            )
            if aiWalls.isEmpty {
                placeholder
            } else {
                LazyVGrid(columns: fixedCols(5), spacing: 16) {
                    ForEach(aiWalls.prefix(10)) { wp in
                        Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "Editorial sets · themed bundles",
                title: "Themed collections.",
                ctaLabel: "All collections →",
                ctaEnabled: true
            )
            if collections.isEmpty {
                placeholder
            } else {
                LazyVGrid(columns: fixedCols(4), spacing: 14) {
                    ForEach(collections.prefix(8)) { c in
                        NavigationLink(value: MainWindow.MainRoute.collection(slug: c.slug, title: c.title)) {
                            CollectionCard(item: c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // ─── Helpers ────────────────────────────────────────────────

    private var heroID: Int? {
        (weekly?.picks.first(where: { $0.isHero }) ?? weekly?.picks.first)?.id
    }

    private func sectionHeader(kicker: String, title: String, ctaLabel: String? = nil, ctaEnabled: Bool = true, onCTA: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: kicker)
                Text(title).font(.display24).foregroundStyle(Color.ink)
            }
            Spacer()
            if let label = ctaLabel {
                Button(action: { onCTA?() }) {
                    Text(label)
                        .font(.kicker).tracking(1.8)
                        .foregroundStyle(ctaEnabled ? Color.ink2 : Color.muted)
                }
                .buttonStyle(.plain)
                .disabled(!ctaEnabled)
            }
        }
    }

    // GridItem(.flexible()) without a minimum gives every column an
    // equal share of the container width — was using .flexible(minimum:
    // 140) which can produce uneven widths when the container narrows.
    // `.top` alignment + matching column spacing 14 (same value as the
    // LazyVGrid's row spacing) keeps cells flush and prevents the
    // shadow-bleed-into-next-row look.
    private func fixedCols(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }

    private var placeholder: some View {
        HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
            .frame(height: 80)
    }

    private func loadAll() async {
        loading = true; defer { loading = false }
        async let weeklyTask: WeeklyCurrent? = try? await APIClient.shared.fetchWeeklyCurrent()
        async let dynTask:    PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 12, dynamicOnly: true)
        async let aiTask:     PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 12, aiOnly: true)
        async let colsTask:   PaginatedData<CollectionItem>? = try? await APIClient.shared.fetchPublicCollections(limit: 12)
        let (w, d, a, c) = await (weeklyTask, dynTask, aiTask, colsTask)
        weekly = w
        dynamicWalls = d?.items ?? []
        aiWalls = a?.items ?? []
        collections = c?.items ?? []
    }

    private func weeklyToWallpaper(_ p: WeeklyPicked) -> Wallpaper {
        Wallpaper(
            id: p.id, slug: p.slug, userID: 0, categoryID: nil, title: p.title, description: "",
            originalURL: p.originalURL, thumbURL: p.thumbURL, previewURL: p.previewURL,
            width: p.width, height: p.height, fileSize: p.fileSize, fileType: p.fileType,
            dominantColor: p.dominantColor, colorPalette: nil, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: p.isDynamic,
            isAIGenerated: p.isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}

// Big hero card at the top of Home. Wide aspect, blurred-bg behind a
// crisp foreground image, kicker / serif title / Open button on top
// of a bottom gradient. Mirrors HeroCard on the web's HomePage.
struct HeroCard: View {
    let pick: WeeklyPicked
    let week: Int
    let year: Int
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL(string: pick.previewURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: pick.dominantColor ?? "#bbb").opacity(0.5)
                }
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    Text("WEEK \(week) · \(year) · HERO PICK")
                        .font(.kicker).tracking(2.2)
                        .foregroundStyle(.white.opacity(0.92))
                    Text(pick.title.isEmpty ? "This week's drop" : pick.title)
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                        Text("Open detail")
                            .font(.sans12)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.18)))
                    .overlay(Capsule().stroke(.white.opacity(0.32), lineWidth: 0.5))
                }
                .padding(28)
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false)
        )
        .scaleEffect(hover ? 1.005 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.18 : 0.08), radius: hover ? 22 : 14, x: 0, y: hover ? 12 : 6)
        .animation(.easeOut(duration: 0.2), value: hover)
        .onHover { entered in
            hover = entered
            if entered {
                PaletteEnv.shared.apply(palette: nil, dominant: pick.dominantColor)
            } else {
                PaletteEnv.shared.resetToDefaults()
            }
        }
    }
}

// Mac Dynamic tile — strict same-shape as MainGridTile so LazyVGrid
// row math is identical. The only visual difference is the chip
// treatment: a single big accent DYNAMIC pill instead of the
// resolution + MAC + AI chip cluster the salon tile uses. No
// caption row, no stacked-offset trick — those were the things
// producing the row-overlap the user kept seeing.
struct MacDynamicTile: View {
    let wallpaper: Wallpaper
    @State private var hover = false

    var body: some View {
        // EXACT same Rectangle().fill.aspectRatio.overlay pattern as
        // MainGridTile (which renders correctly in 'This week's picks'
        // at the top of the page). Rectangle is a Shape with explicit
        // 'fill proposed' size behaviour, so .aspectRatio(.fit) clamps
        // its width × (width * 10/16) bounds before .overlay puts the
        // visible content inside. Tiles in the same row end up the
        // exact same height regardless of the underlying wallpaper's
        // intrinsic aspect ratio.
        Rectangle()
            .fill(Color.clear)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay {
                ZStack(alignment: .topLeading) {
                    Color(hex: wallpaper.dominantColor ?? "#bbb").opacity(0.55)
                    CachedAsyncImage(url: URL(string: wallpaper.displayURL)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .clipped()

                    LinearGradient(
                        colors: [Color.black.opacity(0.18), .clear, .clear, Color.black.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .opacity(hover ? 1 : 0.65)
                    .allowsHitTesting(false)

                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("DYNAMIC").font(.mono10).tracking(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accent))
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false))
                .shadow(color: Color.accent.opacity(hover ? 0.22 : 0.04),
                        radius: hover ? 8 : 3,
                        x: 0, y: hover ? 4 : 1)
            }
            .animation(.easeOut(duration: 0.18), value: hover)
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
