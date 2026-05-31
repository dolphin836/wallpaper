import SwiftUI

// Home landing. Four stacked sections per the design review:
//   1. This week's picks   (latest weekly slate, hero + tile rail)
//   2. Mac Dynamic         (dynamic_only=true)
//   3. AI                  (ai_only=true)
//   4. Collections         (recent public collections)
//
// Each section: kicker + serif headline + small grid + "see all"
// link. The 'see all' links jump to the matching Discover filter or
// Collections page.
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
                weeklySection
                dynamicSection
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
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: weekly.map { "Week \($0.week) · \($0.year)" } ?? "Curated each Friday",
                title: "This week's picks",
                ctaLabel: "VIEW WEEK →",
                ctaEnabled: weekly != nil,
                onCTA: { if let w = weekly { onOpenWeek(w.year, w.week) } }
            )
            if let picks = weekly?.picks, !picks.isEmpty {
                LazyVGrid(columns: cols(min: 220), spacing: 12) {
                    ForEach(picks.prefix(8)) { p in
                        let wp = weeklyToWallpaper(p)
                        Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                            .buttonStyle(.plain)
                    }
                }
            } else {
                emptyOrLoading
            }
        }
    }

    private var dynamicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "Mac · animated · multi-frame",
                title: "Mac Dynamic Wallpapers",
                ctaLabel: nil
            )
            if dynamicWalls.isEmpty {
                emptyOrLoading
            } else {
                LazyVGrid(columns: cols(min: 240), spacing: 12) {
                    ForEach(dynamicWalls.prefix(8)) { wp in
                        Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                kicker: "Synthetic · model-generated",
                title: "AI Wallpapers",
                ctaLabel: nil
            )
            if aiWalls.isEmpty {
                emptyOrLoading
            } else {
                LazyVGrid(columns: cols(min: 240), spacing: 12) {
                    ForEach(aiWalls.prefix(8)) { wp in
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
                kicker: "Themed lists · community + editors",
                title: "Collections",
                ctaLabel: nil
            )
            if collections.isEmpty {
                emptyOrLoading
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(collections.prefix(6)) { c in
                        NavigationLink(value: MainWindow.MainRoute.collection(slug: c.slug, title: c.title)) {
                            CollectionCard(item: c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // ─── Header helper ─────────────────────────────────────────

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

    private func cols(min: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: min, maximum: 360), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if loading {
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .frame(height: 80)
        } else {
            Text("Nothing here yet.")
                .font(.sans12).foregroundStyle(Color.muted)
                .padding(.vertical, 24)
        }
    }

    // ─── Loading ───────────────────────────────────────────────

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
            dominantColor: p.dominantColor, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: p.isDynamic,
            isAIGenerated: p.isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}
