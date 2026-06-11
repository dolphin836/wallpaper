import SwiftUI

// Home — the curated shelf, mirroring the web/Mac home: this week's
// picks, community collections, then AI and Live rails. Everything
// links deeper; nothing here paginates.
struct HomeView: View {
    @State private var weekly: WeeklyCurrent?
    @State private var collections: [CollectionItem] = []
    @State private var aiPicks: [Wallpaper] = []
    @State private var livePicks: [Wallpaper] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: "Home")
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let loadError, weekly == nil && aiPicks.isEmpty {
                            ErrorRetryView(message: loadError) { Task { await load() } }
                        } else {
                            if let weekly, !weekly.picks.isEmpty {
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
                            if !livePicks.isEmpty {
                                raitSection(
                                    kicker: "In motion", title: "Live Wallpapers",
                                    items: livePicks, route: FeedRoute(kind: .live))
                            }
                            if weekly == nil && aiPicks.isEmpty && livePicks.isEmpty {
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
                    ForEach(slate.picks) { pick in
                        NavigationLink(value: WallpaperRoute(slug: pick.slug)) {
                            WallpaperTile(wallpaper: pick.asWallpaper)
                                .frame(height: 240)
                        }
                        .buttonStyle(.plain)
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
                            CollectionCard(collection: collection)
                                .frame(width: 250)
                        }
                        .buttonStyle(.plain)
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
                        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private func load() async {
        do {
            async let weeklyReq = APIClient.shared.fetchWeeklyCurrent()
            async let collectionsReq = APIClient.shared.fetchPublicCollections(limit: 10)
            async let aiReq = APIClient.shared.fetchWallpapers(limit: 10, aiOnly: true)
            async let liveReq = APIClient.shared.fetchWallpapers(limit: 10, dynamicOnly: true)

            weekly = try? await weeklyReq
            collections = (try? await collectionsReq.items) ?? []
            aiPicks = (try? await aiReq.items) ?? []
            livePicks = (try? await liveReq.items) ?? []
            if weekly == nil && collections.isEmpty && aiPicks.isEmpty && livePicks.isEmpty {
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

// Pushable filtered grids ("See all" behind the AI / Live rails).
struct FeedRoute: Hashable {
    enum Kind: Hashable {
        case ai
        case live
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
        .navigationTitle(kind == .ai ? "AI Wallpapers" : "Live Wallpapers")
        .inlineNavTitle()
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
                    dynamicOnly: kind == .live,
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
