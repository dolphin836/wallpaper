import SwiftUI

// Main browse surface — mirrors the web Discover page: feed switcher
// (Latest / Popular / For You / Live / AI), category chips, search, and
// an infinite-scroll grid.
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

    @State private var feed: Feed = .latest
    @State private var categories: [Category] = []
    @State private var selectedCategory: Category?
    @State private var searchText = ""
    @State private var submittedSearch = ""

    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?
    // Monotonic token: bumping it cancels stale in-flight page loads
    // when the user switches feed/category/search mid-request.
    @State private var loadGeneration = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: "Discover")
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    searchField
                    feedPicker
                    categoryChips
                    if let loadError, wallpapers.isEmpty {
                        ErrorRetryView(message: loadError) { reload() }
                    } else if wallpapers.isEmpty && loading {
                        WallpaperGridSkeleton(count: 8)
                    } else if wallpapers.isEmpty {
                        EmptyStateView(kicker: "No matches", message: "Nothing in the archive fits those filters yet.")
                    } else {
                        WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) {
                            loadNextPage()
                        }
                        if loading { LoadingFooter() }
                        if !hasMore {
                            Kicker(text: "End of archive")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.top, 4)
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
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty && !submittedSearch.isEmpty {
                    submittedSearch = ""
                    reload()
                }
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

    // In-page search (the system .searchable bar needs the navigation
    // bar, which the custom top toolbar replaces).
    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
            TextField("Search wallpapers", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Color.ink)
                .onSubmit {
                    submittedSearch = searchText
                    reload()
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        // Borderless fill: search recedes behind the pill rows instead
        // of stacking a third outlined row of chrome.
        .background(Color.paper2, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.top, 4)
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
                        Text(f.rawValue)
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
            .padding(.horizontal, 12)
        }
    }

    private var visibleFeeds: [Feed] {
        // For You needs interaction signals, so it's signed-in only —
        // same gate the web applies.
        auth.isLoggedIn ? Feed.allCases : Feed.allCases.filter { $0 != .forYou }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("All", isOn: selectedCategory == nil) {
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
            .padding(.horizontal, 12)
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
                search: submittedSearch.isEmpty ? nil : submittedSearch,
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
