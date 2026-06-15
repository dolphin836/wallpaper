import SwiftUI

// Home — a phone-first editorial front page: the last four weekly
// slates as an auto-paging album, then compact two-row previews for
// latest wallpapers and latest collections.
struct HomeView: View {
    @Environment(UIPrefs.self) private var prefs
    @Environment(TabRouter.self) private var router

    @State private var weeklyArchive: [WeeklyArchiveEntry] = []
    @State private var latestWallpapers: [Wallpaper] = []
    @State private var latestCollections: [CollectionItem] = []
    @State private var loadError: String?
    @State private var carouselIndex = 0

    private let carouselTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: L10n.strings(for: prefs.language).home)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let loadError, weeklyArchive.isEmpty, latestWallpapers.isEmpty, latestCollections.isEmpty {
                            ErrorRetryView(message: loadError) { Task { await load() } }
                        } else {
                            if !weeklyArchive.isEmpty {
                                weeklyAlbumSection
                            }
                            if !latestWallpapers.isEmpty {
                                latestWallpapersSection
                            }
                            if !latestCollections.isEmpty {
                                latestCollectionsSection
                            }
                            if weeklyArchive.isEmpty && latestWallpapers.isEmpty && latestCollections.isEmpty {
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
            .navigationDestination(for: WeeklyArchiveRoute.self) { _ in
                WeeklyArchiveView()
            }
            .navigationDestination(for: WeeklyArchiveEntry.self) { entry in
                WeeklyWeekView(year: entry.year, week: entry.week)
            }
            .refreshable { await load() }
            .task { if weeklyArchive.isEmpty { await load() } }
            .onReceive(carouselTimer) { _ in
                guard weeklyArchive.count > 1 else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    carouselIndex = (carouselIndex + 1) % min(weeklyArchive.count, 4)
                }
            }
        }
    }

    // ─── sections ────────────────────────────────────────────────

    private var weeklyAlbumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionRow(
                kicker: L10n.strings(for: prefs.language).weeklyKicker,
                title: L10n.strings(for: prefs.language).recentWeekly,
                route: WeeklyArchiveRoute()
            )

            TabView(selection: $carouselIndex) {
                ForEach(Array(weeklyArchive.prefix(4).enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: entry) {
                        WeeklyAlbumCard(entry: entry, index: index, count: min(weeklyArchive.count, 4))
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.pressable)
                    .tag(index)
                }
            }
            .weeklyCarouselStyle()
            .frame(height: 336)
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
                    RailSkeleton(height: i == 0 ? 316 : 210)
                }
            }
        }
    }

    private var latestWallpapersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionRow(
                kicker: L10n.strings(for: prefs.language).latest,
                title: L10n.strings(for: prefs.language).latestWallpapers
            ) {
                switchToTab(1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(latestWallpapers.prefix(4)) { wallpaper in
                    NavigationLink(value: WallpaperRoute(slug: wallpaper.slug)) {
                        WallpaperTile(wallpaper: wallpaper)
                            .frame(height: 218)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var latestCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionRow(
                kicker: L10n.strings(for: prefs.language).collectionsKicker,
                title: L10n.strings(for: prefs.language).latestCollections
            ) {
                switchToTab(3)
            }
            LazyVStack(spacing: 10) {
                ForEach(latestCollections.prefix(2)) { collection in
                    NavigationLink(value: collection) {
                        CollectionCard(collection: collection, height: 148)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func sectionRow(kicker: String, title: String, route: some Hashable) -> some View {
        HStack(alignment: .bottom) {
            SectionHeader(kicker: kicker, title: title)
            Spacer()
            NavigationLink(value: route) {
                sectionActionLabel(L10n.strings(for: prefs.language).viewAll)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 12)
    }

    private func sectionRow(kicker: String, title: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .bottom) {
            SectionHeader(kicker: kicker, title: title)
            Spacer()
            Button(action: action) {
                sectionActionLabel(L10n.strings(for: prefs.language).seeMore)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 12)
    }

    private func sectionActionLabel(_ title: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.accentInk)
    }

    private func switchToTab(_ tag: Int) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            router.selection = tag
        }
    }

    private func load() async {
        do {
            async let archiveReq = APIClient.shared.fetchWeeklyArchive(limit: 4)
            async let wallpapersReq = APIClient.shared.fetchWallpapers(limit: 4)
            async let collectionsReq = APIClient.shared.fetchPublicCollections(limit: 2)

            weeklyArchive = (try? await archiveReq) ?? []
            latestWallpapers = (try? await wallpapersReq.items) ?? []
            latestCollections = (try? await collectionsReq.items) ?? []
            carouselIndex = min(carouselIndex, max(weeklyArchive.count - 1, 0))
            if weeklyArchive.isEmpty && latestWallpapers.isEmpty && latestCollections.isEmpty {
                _ = try await APIClient.shared.fetchWeeklyArchive(limit: 1)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct WeeklyAlbumCard: View {
    let entry: WeeklyArchiveEntry
    let index: Int
    let count: Int

    @Environment(UIPrefs.self) private var prefs

    private var accent: Color {
        Color(hex: entry.accentColor ?? entry.dominantColor) ?? Color.accent
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            albumLayer(offset: CGSize(width: 22, height: 18), scale: 0.88, opacity: 0.34)
            albumLayer(offset: CGSize(width: 11, height: 9), scale: 0.94, opacity: 0.55)
            coverLayer
        }
        .padding(.trailing, 22)
        .padding(.bottom, 18)
    }

    private var coverLayer: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay(
                    CachedAsyncImage(url: URL(string: entry.coverURL), maxPixelDimension: 1200) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(accent.opacity(0.72))
                    }
                )
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.70)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: L10n.strings(for: prefs.language).week, entry.week))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.lightText)
                    .lineLimit(1)
                Text(String(format: L10n.strings(for: prefs.language).picksCount, entry.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lightText.opacity(0.78))
            }
            .padding(18)

            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? Color.lightText : Color.lightText.opacity(0.38))
                        .frame(width: dot == index ? 7 : 5, height: dot == index ? 7 : 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 316)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.24), radius: 24, y: 14)
    }

    private func albumLayer(offset: CGSize, scale: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(accent.opacity(opacity))
            .overlay(
                CachedAsyncImage(url: URL(string: entry.coverURL), maxPixelDimension: 520) { image in
                    image.resizable().aspectRatio(contentMode: .fill).opacity(0.28)
                } placeholder: {
                    accent.opacity(opacity)
                }
            )
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .offset(offset)
            .scaleEffect(scale)
            .blur(radius: 0.2)
    }
}

private extension View {
    @ViewBuilder
    func weeklyCarouselStyle() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
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
