import SwiftUI

// Main browse surface — mirrors the web Discover page: feed switcher
// (Latest / Popular / For You / Live / AI), category chips, search, and
// an infinite-scroll grid.
struct DiscoverView: View {
    enum Feed: String, CaseIterable, Identifiable {
        case latest = "Latest"
        case popular = "Popular"
        case forYou = "For You"
        case live = "Live"
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    feedPicker
                    categoryChips
                    if let loadError, wallpapers.isEmpty {
                        ErrorRetryView(message: loadError) { reload() }
                    } else {
                        WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) {
                            loadNextPage()
                        }
                        if loading { LoadingFooter() }
                        if !hasMore && !wallpapers.isEmpty {
                            Text("That's everything")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .navigationTitle("Wallpaper Exchange")
            .inlineNavTitle()
            .navigationDestination(for: WallpaperRoute.self) { route in
                WallpaperDetailView(slug: route.slug)
            }
            .searchable(text: $searchText, prompt: "Search wallpapers")
            .onSubmit(of: .search) {
                submittedSearch = searchText
                reload()
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

    private var feedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleFeeds) { f in
                    Button {
                        guard feed != f else { return }
                        feed = f
                        reload()
                    } label: {
                        Text(f.rawValue)
                            .font(.subheadline.weight(feed == f ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                feed == f ? Color.primary : Color.shimGray6,
                                in: Capsule()
                            )
                            .foregroundStyle(feed == f ? Color.shimBackground : .primary)
                    }
                    .buttonStyle(.plain)
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
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.shimGray6, in: Capsule())
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
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
                dynamicOnly: feed == .live,
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
