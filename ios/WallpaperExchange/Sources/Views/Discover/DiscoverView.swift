import SwiftUI

// Main browse surface — mirrors the web Discover page's feed switcher,
// category chips, and infinite-scroll grid. Search stays on web/Mac;
// the iOS browse surface is intentionally lighter.
struct DiscoverView: View {
    // No Live feed on iOS — the platform can't use video / macOS-dynamic
    // wallpapers, so the client hides that whole content class.
    enum Feed: String, CaseIterable, Identifiable {
        case latest = "Latest"
        case popular = "Popular"
        case forYou = "For You"
        case ai = "AI"
        var id: String { rawValue }
    }

    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs

    @State private var feed: Feed = .latest
    @State private var categories: [Category] = []
    @State private var selectedCategory: Category?

    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?
    // Monotonic token: bumping it cancels stale in-flight page loads
    // when the user switches feed/category mid-request.
    @State private var loadGeneration = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: L10n.strings(for: prefs.language).discover)
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filterSurface
                    if let loadError, wallpapers.isEmpty {
                        ErrorRetryView(message: loadError) { reload() }
                    } else if wallpapers.isEmpty && loading {
                        WallpaperGridSkeleton(count: 8)
                    } else if wallpapers.isEmpty {
                        EmptyStateView(
                            kicker: L10n.strings(for: prefs.language).noMatches,
                            message: L10n.strings(for: prefs.language).noMatchesMessage
                        )
                    } else {
                        WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) {
                            loadNextPage()
                        }
                        if loading { LoadingFooter() }
                        if !hasMore {
                            Kicker(text: L10n.strings(for: prefs.language).endOfArchive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.top, 6)
                }
                .background(Color.clear)
            }
            .background(PageMesh())
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .safeAreaInset(edge: .bottom) { FloatingTabBar() }
            .navigationDestination(for: WallpaperRoute.self) { route in
                WallpaperDetailView(slug: route.slug)
            }
            .refreshable { await load(reset: true) }
            .task {
                if wallpapers.isEmpty { reload() }
                if categories.isEmpty {
                    categories = (try? await APIClient.shared.fetchCategories()) ?? []
                }
            }
        }
    }

    private var filterSurface: some View {
        VStack(spacing: 10) {
            feedPicker
            categoryChips
        }
        .padding(10)
        .background(Color.paper2.opacity(0.62), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.hair.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    @Namespace private var feedPillNS

    private var feedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleFeeds) { f in
                    Button {
                        guard feed != f else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            feed = f
                        }
                        reload()
                    } label: {
                        Text(feedTitle(f))
                            .font(.subheadline.weight(feed == f ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                // The ink fill slides between pills.
                                if feed == f {
                                    Capsule()
                                        .fill(Color.ink)
                                        .matchedGeometryEffect(id: "feed-pill", in: feedPillNS)
                                } else {
                                    Capsule()
                                        .fill(Color.paper2)
                                        .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                                }
                            }
                            .foregroundStyle(feed == f ? Color.paper : Color.ink2)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var visibleFeeds: [Feed] {
        // For You needs interaction signals, so it's signed-in only —
        // same gate the web applies.
        auth.isLoggedIn ? Feed.allCases : Feed.allCases.filter { $0 != .forYou }
    }

    private func feedTitle(_ feed: Feed) -> String {
        let s = L10n.strings(for: prefs.language)
        switch feed {
        case .latest: return s.latest
        case .popular: return s.popular
        case .forYou: return s.forYou
        case .ai: return s.ai
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(L10n.strings(for: prefs.language).all, isOn: selectedCategory == nil) {
                    guard selectedCategory != nil else { return }
                    selectedCategory = nil
                    reload()
                }
                ForEach(categories) { category in
                    chipButton(category.name, isOn: selectedCategory == category) {
                        selectedCategory = selectedCategory == category ? nil : category
                        reload()
                    }
                }
            }
        }
    }

    private func chipButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            Text(title)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentSoft : Color.paper2, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.accent.opacity(0.45) : Color.hair, lineWidth: 1)
                )
                .foregroundStyle(isOn ? Color.accentInk : Color.muted)
        }
        .buttonStyle(.plain)
        .archiveSelectionFeedback(trigger: isOn)
    }

    private func reload() {
        loadGeneration += 1
        wallpapers = []
        cursor = nil
        hasMore = true
        loadError = nil
        loadNextPage()
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        if reset {
            loadGeneration += 1
            cursor = nil
            hasMore = true
        }
        let generation = loadGeneration
        loading = true
        defer { loading = false }
        do {
            if feed == .forYou {
                let items = try await APIClient.shared.fetchForYou(limit: 30)
                guard generation == loadGeneration else { return }
                wallpapers = items
                hasMore = false
                loadError = nil
                return
            }
            let page = try await APIClient.shared.fetchWallpapers(
                cursor: reset ? nil : cursor,
                limit: 24,
                aiOnly: feed == .ai,
                categoryID: selectedCategory?.id,
                sort: feed == .popular ? "popular" : nil
            )
            guard generation == loadGeneration else { return }
            if reset {
                wallpapers = page.items
            } else {
                wallpapers.append(contentsOf: page.items)
            }
            cursor = page.nextCursor
            hasMore = page.hasMore
            loadError = nil
        } catch {
            guard generation == loadGeneration else { return }
            loadError = error.localizedDescription
        }
    }
}
