import SwiftUI

// Home page layout matches the web's HomePage:
//   1. Hero card (big featured pick from /weekly-picks/current,
//      tinted by its palette).
//   2. This week's picks rest of slate — 5-column grid.
//   3. Live — Mac dynamic (.heic solar/h24) + video wallpapers,
//      unified under one "Live" pill. 4-column grid.
//   4. AI Lab — 5-column grid.
//   5. Themed collections — 4-column rail.
struct HomeView: View {
    var onPick: (Wallpaper) -> Void
    var onOpenWeek: (Int, Int) -> Void
    // "Browse more" CTAs route to the matching top-level view.
    var onOpenDiscover: (DiscoverView.Filter) -> Void = { _ in }
    var onOpenCollections: () -> Void = {}
    var onOpenWeeklyArchive: () -> Void = {}

    @State private var weekly: WeeklyCurrent?
    @State private var liveWalls: [Wallpaper] = []
    @State private var aiWalls: [Wallpaper] = []
    @State private var collections: [CollectionItem] = []
    // Per-section loading flags so each row can show its own skeletons
    // and one slow endpoint doesn't blank the entire page. Matches the
    // web HomePage's independent useState pattern.
    @State private var weeklyLoading = true
    @State private var liveLoading = true
    @State private var aiLoading = true
    @State private var collectionsLoading = true
    @State private var allFailed = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Web .h3-row has padding-top 120px between rows. The first
            // row gets 72px (handled by VStack initial spacing).
            VStack(alignment: .leading, spacing: 100) {
                if let hero = weekly?.picks.first(where: { $0.isHero }) ?? weekly?.picks.first {
                    HeroCard(pick: hero, week: weekly!.week, year: weekly!.year, onTap: { onPick(weeklyToWallpaper(hero)) })
                } else if weeklyLoading {
                    SkeletonTile(variant: .hero)
                }
                if allFailed {
                    RemoteLoadErrorView(message: "The home feed could not load. Please try again.") {
                        Task { await loadAll() }
                    }
                } else {
                    weeklySection
                    liveSection
                    aiSection
                    collectionsSection
                }
            }
            // WindowChrome.topInset matches the sidebar logo's top
            // padding, so the hero card and the sidebar logo line up
            // on the same baseline (windowed AND full-screen).
            .padding(.horizontal, 32)
            .padding(.top, WindowChrome.topInset)
            .padding(.bottom, 60)
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .background(TransparentAppKitBackground())
        .task { await loadAll() }
    }

    // ─── Sections ──────────────────────────────────────────────

    private var weeklySection: some View {
        let restPicks = (weekly?.picks ?? []).filter { p in p.id != heroID } .prefix(5)
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: weekly.map { "Curation · Week \($0.week)" } ?? "Curated each Friday",
                title: "picks.",
                accent: "This week's",
                ctaLabel: "View archive →",
                ctaEnabled: true,
                onCTA: { onOpenWeeklyArchive() }
            )
            if !restPicks.isEmpty {
                // Web .h3-weekly: aspect-ratio 4/5 (portrait editorial)
                LazyVGrid(columns: fixedCols(5), spacing: 16) {
                    ForEach(restPicks) { p in
                        let wp = weeklyToWallpaper(p)
                        Button(action: { onPick(wp) }) {
                            MainGridTile(wallpaper: wp, aspectRatio: 4.0 / 5.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if weeklyLoading {
                LazyVGrid(columns: fixedCols(5), spacing: 16) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonTile(variant: .weekly)
                    }
                }
            }
        }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "Motion · hover to preview",
                title: "wallpapers.",
                accent: "Live",
                ctaLabel: "All live wallpapers →",
                ctaEnabled: true,
                onCTA: { onOpenDiscover(.live) }
            )
            if liveWalls.isEmpty {
                if liveLoading {
                    LazyVGrid(columns: fixedCols(4), spacing: 14) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonTile(variant: .live)
                        }
                    }
                }
            } else {
                LazyVGrid(columns: fixedCols(4), spacing: 14) {
                    ForEach(liveWalls.prefix(4)) { wp in
                        Button(action: { onPick(wp) }) {
                            MainGridTile(wallpaper: wp, aspectRatio: 16.0 / 10.0)
                        }
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
                title: "this week.",
                accent: "Generated",
                ctaLabel: "All AI wallpapers →",
                ctaEnabled: true,
                onCTA: { onOpenDiscover(.ai) }
            )
            if aiWalls.isEmpty {
                if aiLoading {
                    LazyVGrid(columns: fixedCols(5), spacing: 16) {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonTile(variant: .ai)
                        }
                    }
                }
            } else {
                // Web .h3-ai: aspect-ratio 1/1 (square with foil sweep)
                LazyVGrid(columns: fixedCols(5), spacing: 16) {
                    ForEach(aiWalls.prefix(5)) { wp in
                        Button(action: { onPick(wp) }) {
                            MainGridTile(wallpaper: wp, aspectRatio: 1.0)
                        }
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
                title: "collections.",
                accent: "Themed",
                ctaLabel: "All collections →",
                ctaEnabled: true,
                onCTA: { onOpenCollections() }
            )
            if collections.isEmpty {
                if collectionsLoading {
                    LazyVGrid(columns: fixedCols(4), spacing: 14) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonTile(variant: .collection)
                        }
                    }
                }
            } else {
                LazyVGrid(columns: fixedCols(4), spacing: 14) {
                    ForEach(collections.prefix(4)) { c in
                        NavigationLink(value: MainWindow.MainRoute.collection(slug: c.slug, title: c.title)) {
                            CollectionTileCard(item: c)
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

    // Web .h3-row-head:
    //   align-items: end (NOT first-text-baseline); margin-bottom 22
    //   .h3-sub:   mono 11px / tracking 0.14em / caps / muted / mb 12
    //   h2:        display 32 / weight 400 / line-height 1 / -0.01em tracking
    //   h2 em:     weight 500 / accent color / NO italic
    //   .h3-more:  13px / ink / 1px bottom border ink2 / pad-bottom 2
    private func sectionHeader(kicker: String,
                               title: String,
                               accent: String? = nil,
                               ctaLabel: String? = nil,
                               ctaEnabled: Bool = true,
                               onCTA: (() -> Void)? = nil) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(kicker.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.muted)
                titleText(title: title, accent: accent)
            }
            Spacer()
            if let label = ctaLabel {
                Button(action: { onCTA?() }) {
                    Text(label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ctaEnabled ? Color.ink : Color.muted)
                        .padding(.bottom, 2)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(ctaEnabled ? Color.ink2 : Color.muted)
                                .frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!ctaEnabled)
            }
        }
        .padding(.bottom, 10)
    }

    // Render the section title with an inline accent word. Web pattern
    // is `<em>Word</em> rest.`, where em = weight 500 + accent color.
    @ViewBuilder
    private func titleText(title: String, accent: String?) -> some View {
        if let a = accent, !a.isEmpty {
            (
                Text(a)
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .foregroundColor(Color.accent)
                +
                Text(" " + title)
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundColor(Color.ink)
            )
            .tracking(-0.3)
        } else {
            Text(title)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .tracking(-0.3)
                .foregroundStyle(Color.ink)
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

    // Four independent fetches in parallel; each section flips its own
    // loading flag off as soon as its endpoint returns. This is the
    // pattern web HomePage uses — one slow row doesn't stall the
    // skeleton swap for the others.
    private func loadAll() async {
        weeklyLoading = true
        liveLoading = true
        aiLoading = true
        collectionsLoading = true
        allFailed = false

        async let weeklyTask: WeeklyCurrent? = try? await APIClient.shared.fetchWeeklyCurrent()
        async let liveTask:   PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 12, dynamicOnly: true)
        async let aiTask:     PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 12, aiOnly: true)
        async let colsTask:   PaginatedData<CollectionItem>? = try? await APIClient.shared.fetchPublicCollections(limit: 12)

        let w = await weeklyTask
        weekly = w
        weeklyLoading = false

        let l = await liveTask
        liveWalls = l?.items ?? []
        liveLoading = false

        let a = await aiTask
        aiWalls = a?.items ?? []
        aiLoading = false

        let c = await colsTask
        collections = c?.items ?? []
        collectionsLoading = false

        allFailed = w == nil && l == nil && a == nil && c == nil
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

// Hero card at the top of Home. Mirrors the web's HomePage HeroCard:
//   • 16:9 aspect, 24pt rounded
//   • Bottom-gradient overlay
//   • Left: Curation · Week N · YEAR kicker + WxH · file-size meta
//   • Right: white "○ Trade for 1" CTA pill with coin glyph
//   • Top-right: small resolution chip
// No serif title in the overlay — web hero leads with the image and
// metadata, not text. Hover lifts the card and deepens the shadow.
struct HeroCard: View {
    let pick: WeeklyPicked
    let week: Int
    let year: Int
    let onTap: () -> Void
    @State private var hover = false

    // Mirrors ResChip in components/WallpaperTile.tsx:
    //   >=7680→8K, >=3840→4K, >=2560→2K, >=1920→1080P, >=1280→720P, else hidden
    private var resolutionLabel: String? {
        let px = max(pick.width, pick.height)
        if px >= 7680 { return "8K" }
        if px >= 3840 { return "4K" }
        if px >= 2560 { return "2K" }
        if px >= 1920 { return "1080P" }
        if px >= 1280 { return "720P" }
        return nil
    }

    // Web format: "1920×1080 · 2.3 MB" — 1 decimal under 10 MB.
    private var fileSizeLabel: String {
        let mb = Double(pick.fileSize) / 1024.0 / 1024.0
        return mb >= 10 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Image fills whatever frame the OUTER aspect modifier
                // gives the ZStack. Putting .aspectRatio on the image
                // here didn't constrain the ZStack — image's natural
                // aspect leaked through, making the hero too tall and
                // pushing the bottom overlay off-screen.
                CachedAsyncImage(url: URL(string: pick.previewURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: pick.dominantColor ?? "#bbb").opacity(0.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Bottom gradient — web uses linear-gradient(180deg,
                // transparent, rgba(0,0,0,0.4))
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Top-right resolution chip — web .h3-hero .h3-res-chip
                //   top: 16px; right: 16px
                //   padding: 2px 8px
                //   font-size: 10px (mono, weight 600, letter-spacing 0.04em)
                //   background: oklch(98% 0.005 240 / 0.75)  ← LIGHT pill
                //   color: oklch(36% 0.012 240)              ← DARK text
                if let res = resolutionLabel {
                    VStack {
                        HStack {
                            Spacer()
                            Text(res)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(0.4)
                                .foregroundStyle(Color(hex: "#54585f"))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.75))
                                )
                                .padding(.top, 16).padding(.trailing, 16)
                        }
                        Spacer()
                    }
                }

                // Bottom overlay — web .h3-hero-overlay
                //   padding: 26px 30px 24px (top right/left bottom)
                //   display: flex, align-items: end, justify-content: space-between, gap: 24px
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        // .h3-kicker — mono 10px, letter-spacing 0.16em,
                        // uppercase, color rgba(255,255,255,0.85)
                        Text("CURATION · WEEK \(week) · \(year)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.85))
                        // .h3-meta — mono 12.5px, opacity 0.78
                        Text("\(pick.width)×\(pick.height) · \(fileSizeLabel)")
                            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Spacer(minLength: 0)
                    // .h3-cta — padding 13px 22px, font 13.5/600
                    //   background white, color oklch(20% 0.014 240)
                    //   border-radius 999px
                    //   box-shadow 0 6px 22px -6px rgba(0,0,0,0.4)
                    HStack(spacing: 10) {
                        // .h3-coin — 11×11, linear-gradient(135deg,#f4ae66,#d57130)
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#f4ae66"), Color(hex: "#d57130")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 11, height: 11)
                        Text("Trade for 1")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#202229"))
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .background(Capsule().fill(.white))
                    .shadow(color: Color.black.opacity(0.40), radius: 22, x: 0, y: 6)
                }
                .padding(.top, 26)
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Constrain the WHOLE ZStack to 16:9 so the image,
            // gradient, and bottom overlay all share the same bounds.
            // Putting aspect on the image alone let it overgrow.
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        // Drop-shadow stack — web has 3 layers (inset top white + 2 dark
        // drops). SwiftUI doesn't do multi-layer inset shadows cleanly,
        // so collapse to a single combined drop that hits the same
        // weight under default lighting.
        .scaleEffect(hover ? 1.005 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.35 : 0.30),
                radius: hover ? 40 : 30,
                x: 0, y: hover ? 14 : 10)
        .animation(.easeOut(duration: 0.6), value: hover)
        .onHover { entered in
            hover = entered
            if entered {
                PaletteEnv.shared.apply(palette: pick.colorPalette, dominant: pick.dominantColor)
            } else {
                PaletteEnv.shared.resetToDefaults()
            }
        }
    }
}

// Live tile — strict same-shape as MainGridTile so LazyVGrid row
// math is identical. The only visual difference is the chip
// treatment: a single accent "LIVE" pill (play-triangle icon),
// shown when the wallpaper is either a Mac dynamic (.heic
// solar/h24) or a video. Matches the web's unified Live concept.
struct MacDynamicTile: View {
    let wallpaper: Wallpaper
    @State private var hover = false

    // GeometryReader-driven sizing — the previous attempts all relied on
    // .aspectRatio modifiers, which can fall through to a child view's
    // intrinsic size when the parent doesn't propose enough constraint.
    // Inside a LazyVGrid cell that produced tiles whose height tracked
    // the underlying wallpaper image's aspect — portrait Big Sur became
    // a tall portrait tile while landscape Sonoma stayed wide.
    //
    // GeometryReader fills the cell's proposed width; we then frame the
    // ZStack to width × (width * 10/16) and pin the GeometryReader to
    // that height too via `.frame(height:)` on the outer container.
    // Every Mac Dynamic tile is now exactly the same height regardless
    // of the source image's orientation.
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.width * 10.0 / 16.0
            ZStack(alignment: .topLeading) {
                Color(hex: wallpaper.dominantColor ?? "#bbb").opacity(0.55)
                CachedAsyncImage(url: URL(string: wallpaper.displayURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(width: proxy.size.width, height: h)
                .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.18), .clear, .clear, Color.black.opacity(0.30)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(hover ? 1 : 0.65)
                .allowsHitTesting(false)

                // .tile-chip family — light translucent pill, dark text
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 8, weight: .semibold))
                    Text("LIVE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                }
                .foregroundStyle(Color(red: 0.20, green: 0.21, blue: 0.23))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.78)))
                .padding(10)
            }
            .frame(width: proxy.size.width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false))
            .shadow(color: Color.accent.opacity(hover ? 0.22 : 0.04),
                    radius: hover ? 8 : 3,
                    x: 0, y: hover ? 4 : 1)
        }
        // Match the GeometryReader's internal height. SwiftUI's
        // GeometryReader doesn't propose a size of its own — the
        // outer container has to know it. Aspect-ratio modifier on
        // the GeometryReader gives the LazyVGrid the right cell
        // height to allocate.
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
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
