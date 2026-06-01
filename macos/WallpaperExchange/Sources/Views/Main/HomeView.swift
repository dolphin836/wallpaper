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

    @State private var weekly: WeeklyCurrent?
    @State private var liveWalls: [Wallpaper] = []
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
                liveSection
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

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "Motion · hover to preview",
                title: "Live wallpapers.",
                ctaLabel: "All live →",
                ctaEnabled: true
            )
            if liveWalls.isEmpty {
                placeholder
            } else {
                LazyVGrid(columns: fixedCols(4), spacing: 14) {
                    ForEach(liveWalls.prefix(8)) { wp in
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
        async let liveTask:   PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 12, dynamicOnly: true)
        async let aiTask:     PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 12, aiOnly: true)
        async let colsTask:   PaginatedData<CollectionItem>? = try? await APIClient.shared.fetchPublicCollections(limit: 12)
        let (w, l, a, c) = await (weeklyTask, liveTask, aiTask, colsTask)
        weekly = w
        liveWalls = l?.items ?? []
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

    private var resolutionLabel: String {
        let px = max(pick.width, pick.height)
        switch px {
        case 7680...:  return "8K"
        case 3840...:  return "4K"
        case 2560...:  return "2K"
        case 1920...:  return "HD"
        default:       return "\(pick.width)×\(pick.height)"
        }
    }

    private var fileSizeLabel: String {
        let mb = Double(pick.fileSize) / 1024.0 / 1024.0
        return mb >= 10 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL(string: pick.previewURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: pick.dominantColor ?? "#bbb").opacity(0.5)
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.40)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Top-right resolution chip — matches web's .h3-res-chip
                VStack {
                    HStack {
                        Spacer()
                        Text(resolutionLabel)
                            .font(.mono10).tracking(0.4)
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.42)))
                            .padding(.top, 16).padding(.trailing, 16)
                    }
                    Spacer()
                }

                // Bottom overlay: kicker + meta on left, CTA on right
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CURATION · WEEK \(week) · \(year)")
                            .font(.mono10).tracking(2.0)
                            .foregroundStyle(.white.opacity(0.88))
                        Text("\(pick.width)×\(pick.height) · \(fileSizeLabel)")
                            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#f4ae66"), Color(hex: "#d57130")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 11, height: 11)
                        Text("Trade for 1").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#202229"))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(.white))
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 30).padding(.bottom, 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 24).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false)
        )
        .scaleEffect(hover ? 1.005 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.22 : 0.10),
                radius: hover ? 28 : 18,
                x: 0, y: hover ? 14 : 8)
        .animation(.easeOut(duration: 0.25), value: hover)
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

                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("LIVE").font(.mono10).tracking(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.accent))
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
