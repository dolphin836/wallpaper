import SwiftUI

// Home — the curated shelf, mirroring the web/Mac home: this week's
// picks, community collections, then the AI rail. (No Live rail on
// iOS — the platform can't use video wallpapers.) Everything links
// deeper; nothing here paginates.
struct HomeView: View {
    @State private var weekly: WeeklyCurrent?
    @State private var collections: [CollectionItem] = []
    @State private var aiPicks: [Wallpaper] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: "Home")
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let loadError, weekly == nil, aiPicks.isEmpty {
                            ErrorRetryView(message: loadError) { Task { await load() } }
                        } else {
                            if let weekly, !weekly.picks.isEmpty {
                                weeklyHero(weekly)
                                weeklySection(weekly)
                            }
                            if !collections.isEmpty {
                                collectionsSection
                            }
                            if !aiPicks.isEmpty {
                                raitSection(
                                    kicker: "Machine dreams", title: "AI Wallpapers",
                                    items: aiPicks, route: FeedRoute(kind: .ai))
                            }
                            if weekly == nil && aiPicks.isEmpty {
                                homeSkeleton
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .background(Color.paper)
            }
            .background(Color.paper)
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .safeAreaInset(edge: .bottom) { FloatingTabBar() }
            .navigationDestination(for: WallpaperRoute.self) { route in
                WallpaperDetailView(slug: route.slug)
            }
            .navigationDestination(for: CollectionItem.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .navigationDestination(for: FeedRoute.self) { route in
                FilteredFeedView(kind: route.kind)
            }
            .navigationDestination(for: WeeklyArchiveRoute.self) { _ in
                WeeklyArchiveView()
            }
            .navigationDestination(for: WeeklyArchiveEntry.self) { entry in
                WeeklyWeekView(year: entry.year, week: entry.week)
            }
            .refreshable { await load() }
            .task { if weekly == nil { await load() } }
        }
    }

    // ─── sections ────────────────────────────────────────────────

    @ViewBuilder
    private func weeklyHero(_ slate: WeeklyCurrent) -> some View {
        let usable = slate.picks.map(\.asWallpaper).filter(\.isUsableOnIOS)
        if let hero = usable.first {
            NavigationLink(value: WallpaperRoute(slug: hero.slug)) {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .overlay(
                            CachedAsyncImage(url: URL(string: hero.displayURL), maxPixelDimension: 1700) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color(hex: hero.dominantColor) ?? Color.paper3)
                            }
                        )
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.10), .black.opacity(0.68)],
                        startPoint: .top, endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            MediaChip(text: "Week \(slate.week)")
                            MediaChip(text: hero.resolutionLabel, tint: Color.black.opacity(0.22))
                        }

                        Text(hero.title)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(Color.lightText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)

                        HStack(spacing: 6) {
                            Text("Open this wallpaper")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lightText.opacity(0.78))
                    }
                    .padding(18)
                }
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: (Color(hex: hero.dominantColor) ?? .black).opacity(0.28), radius: 24, y: 12)
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 12)
        }
    }

    // Mirrors the shelf layout so content landing doesn't reflow.
    private var homeSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        SkeletonBlock(radius: 3).frame(width: 90, height: 9)
                        SkeletonBlock(radius: 5).frame(width: 160, height: 20)
                    }
                    .padding(.horizontal, 12)
                    RailSkeleton(height: i == 0 ? 240 : 190)
                }
            }
        }
    }

    private func weeklySection(_ slate: WeeklyCurrent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionRow(
                kicker: "Week \(slate.week) · \(String(slate.year))",
                title: "Weekly Picks",
                route: WeeklyArchiveRoute()
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Weekly slates can include video picks; drop them on iOS.
                    ForEach(slate.picks.map(\.asWallpaper).filter(\.isUsableOnIOS)) { pick in
                        NavigationLink(value: WallpaperRoute(slug: pick.slug)) {
                            WallpaperTile(wallpaper: pick)
                                .frame(height: 240)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: "Curated shelves", title: "Collections")
                .padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collections) { collection in
                        NavigationLink(value: collection) {
                            CollectionCard(collection: collection, height: 150)
                                .frame(width: 280)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func raitSection(kicker: String, title: String, items: [Wallpaper], route: FeedRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionRow(kicker: kicker, title: title, route: route)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { wallpaper in
                        NavigationLink(value: WallpaperRoute(slug: wallpaper.slug)) {
                            WallpaperTile(wallpaper: wallpaper)
                                .frame(height: 190)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func sectionRow(kicker: String, title: String, route: some Hashable) -> some View {
        HStack(alignment: .bottom) {
            SectionHeader(kicker: kicker, title: title)
            Spacer()
            NavigationLink(value: route) {
                HStack(spacing: 3) {
                    Text("See all")
                        .font(.caption.weight(.medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.accentInk)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 12)
    }

    private func load() async {
        do {
            async let weeklyReq = APIClient.shared.fetchWeeklyCurrent()
            async let collectionsReq = APIClient.shared.fetchPublicCollections(limit: 10)
            async let aiReq = APIClient.shared.fetchWallpapers(limit: 10, aiOnly: true)

            weekly = try? await weeklyReq
            collections = (try? await collectionsReq.items) ?? []
            aiPicks = (try? await aiReq.items) ?? []
            if weekly == nil && collections.isEmpty && aiPicks.isEmpty {
                // Every fetch failed — surface one retryable error instead
                // of an empty shelf.
                _ = try await APIClient.shared.fetchWeeklyCurrent()
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Pushable filtered grid ("See all" behind the AI rail).
struct FeedRoute: Hashable {
    enum Kind: Hashable {
        case ai
    }
    let kind: Kind
}

struct WeeklyArchiveRoute: Hashable {}

struct FilteredFeedView: View {
    let kind: FeedRoute.Kind

    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let loadError, wallpapers.isEmpty {
                    ErrorRetryView(message: loadError) { loadNextPage() }
                } else if wallpapers.isEmpty && loading {
                    WallpaperGridSkeleton(count: 8)
                } else {
                    WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) { loadNextPage() }
                    if loading { LoadingFooter() }
                }
            }
            .padding(.top, 8)
        }
        .background(Color.paper)
        .navigationTitle("AI Wallpapers")
        .inlineNavTitle()
        .showNavBarCompat()
        .task { if wallpapers.isEmpty { loadNextPage() } }
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await APIClient.shared.fetchWallpapers(
                    cursor: cursor,
                    limit: 24,
                    aiOnly: kind == .ai
                )
                wallpapers.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
                loadError = nil
            } catch {
                if wallpapers.isEmpty { loadError = error.localizedDescription }
                hasMore = false
            }
        }
    }
}
