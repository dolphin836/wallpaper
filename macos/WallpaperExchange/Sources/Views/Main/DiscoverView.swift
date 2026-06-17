import SwiftUI

// Main Discover content — mirrors the web Discover page:
//   • one unified toolbar: scrollable category chips on the left,
//     a FILTER dropdown + a size (LG/MD) control on the right
//   • a static device banner (the Mac's stand-in for the web's
//     floating device wall) seeded with the first feed wallpaper
//   • a size-driven wallpaper grid with infinite scroll
//
// The single FilterMode fully specifies what is fetched and how it is
// sorted (no separate sort toggle), matching the web: Latest, Trending,
// For You (signed-in only), My Device, Live, AI Generated.
struct DiscoverView: View {
    let search: String
    var onPick: (Wallpaper) -> Void
    /// When true (used by the legacy device-match sidebar entry) the
    /// initial filter is forced to .myDevice. Discover itself starts on
    /// Latest.
    var deviceMatch: Bool = false
    /// Set when arriving from a Home "browse more" CTA (e.g. Live / AI).
    var initialFilter: Filter? = nil

    @State private var auth = AuthService.shared
    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadError: String?
    @State private var filter: Filter = .latest
    @State private var sizeMode: SizeMode = .lg
    // The wallpaper currently shown on the device mockup. Driven by
    // hovering grid tiles (web "floating wall" feel); falls back to the
    // first feed item.
    @State private var featuredHover: Wallpaper?
    @State private var categories: [Category] = []
    @State private var selectedCategoryID: Int? = nil
    @State private var palette = PaletteEnv.shared

    // Category strip overflow tracking — drives the trailing fade that
    // only shows when the chips are wider than the visible strip (so
    // full-screen, where they all fit, gets no fade).
    @State private var chipsContentW: CGFloat = 0
    @State private var chipsViewportW: CGFloat = 0
    private var chipsOverflow: Bool { chipsContentW > chipsViewportW + 1 }
    private var chipsFadeStart: CGFloat {
        guard chipsViewportW > 28 else { return 0.85 }
        return max(0, (chipsViewportW - 28) / chipsViewportW)
    }

    enum Filter: String, CaseIterable, Hashable {
        case latest = "Latest"
        case trending = "Trending"
        case forYou = "For You"
        case myDevice = "My Device"
        case live = "Live"
        case ai = "AI Generated"

        /// Localized display label — the rawValue stays a stable
        /// identifier and never reaches the API (params are computed).
        var label: String {
            switch self {
            case .latest: L10n.browse.filterLatest
            case .trending: L10n.browse.filterTrending
            case .forYou: L10n.browse.filterForYou
            case .myDevice: L10n.browse.filterMyDevice
            case .live: L10n.browse.filterLive
            case .ai: L10n.browse.filterAI
            }
        }
    }

    enum SizeMode: String, CaseIterable { case md = "MD", lg = "LG" }

    // For You is only meaningful for signed-in users — hide it for
    // guests so the dropdown doesn't surface an option that immediately
    // falls back to Latest.
    private var availableFilters: [Filter] {
        auth.isLoggedIn
            ? [.latest, .trending, .forYou, .myDevice, .live, .ai]
            : [.latest, .trending, .myDevice, .live, .ai]
    }

    private var featuredWallpaper: Wallpaper? {
        featuredHover ?? items.first
    }

    private var gridSpacing: CGFloat {
        switch sizeMode {
        case .lg: 14
        case .md: 12
        }
    }

    private var gridMinimumWidth: CGFloat {
        switch sizeMode {
        case .lg: 300
        case .md: 200
        }
    }

    private var gridColumns: [GridItem] {
        switch sizeMode {
        case .lg: [GridItem(.adaptive(minimum: gridMinimumWidth, maximum: 460), spacing: gridSpacing, alignment: .top)]
        case .md: [GridItem(.adaptive(minimum: gridMinimumWidth, maximum: 300), spacing: gridSpacing, alignment: .top)]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let feedWidth = max(1, proxy.size.width - 80)
            VStack(spacing: 0) {
                discoverHeader

                ScrollView(.vertical, showsIndicators: false) {
                    feed(availableWidth: feedWidth)
                        .padding(.horizontal, 40)
                        .padding(.top, 14)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .zIndex(0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.clear)
        }
        .task(id: "discover-init") {
            if let initialFilter { filter = initialFilter }
            else if deviceMatch { filter = .myDevice }
            if categories.isEmpty {
                if let list = try? await APIClient.shared.fetchCategories() {
                    categories = list.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                }
            }
            await reload()
        }
        .onChange(of: filter) { _, _ in Task { await reload() } }
        .onChange(of: search) { _, _ in Task { await reload() } }
        .onChange(of: selectedCategoryID) { _, _ in Task { await reload() } }
    }

    private var discoverHeader: some View {
        DevicePreviewBanner(
            featured: featuredWallpaper,
            onPick: {
                if let shown = featuredWallpaper {
                    onPick(shown)
                }
            }
        ) {
            toolbar
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .zIndex(2)
    }

    // ── Feed: the scrolling grid + loading / empty / error states.
    // Hovering a tile lifts it into the pinned device mockup above. ──
    @ViewBuilder
    private func feed(availableWidth: CGFloat) -> some View {
        if loading && items.isEmpty {
            WallpaperGridSkeleton(
                columns: gridColumns,
                count: skeletonCardCount(for: availableWidth),
                spacing: gridSpacing
            )
        } else if let err = loadError, items.isEmpty {
            errorBanner(err)
        } else if items.isEmpty {
            RemoteEmptyStateView(
                title: search.isEmpty ? L10n.browse.emptyTitle : L10n.browse.searchEmptyTitle,
                message: search.isEmpty
                    ? L10n.browse.emptyMessage
                    : L10n.browse.searchEmptyMessage,
                symbol: search.isEmpty ? "photo.on.rectangle" : "magnifyingglass"
            )
        } else {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(items) { wp in
                    Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                        .buttonStyle(.plain)
                        .onHover { if $0 { featuredHover = wp } }
                        .onAppear { maybeLoadMore(wp) }
                }
            }
            feedFooter
        }
    }

    private func skeletonCardCount(for availableWidth: CGFloat) -> Int {
        let columns = max(1, Int(floor((availableWidth + gridSpacing) / (gridMinimumWidth + gridSpacing))))
        return columns * 3
    }

    // Infinite-scroll footer — loading spinner, a manual "Load more"
    // fallback, a retry on pagination error, and an end-of-feed marker.
    // Mirrors the web's FeedFooter vocabulary.
    @ViewBuilder
    private var feedFooter: some View {
        Group {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.browse.loadingMore).font(.sans12).foregroundStyle(Color.muted)
                }
            } else if loadError != nil {
                HStack(spacing: 10) {
                    Text(L10n.browse.loadMoreFailed).font(.sans12).foregroundStyle(Color.ink2)
                    Button(L10n.common.retry) { Task { await loadMore() } }.controlSize(.small)
                }
            } else if hasMore {
                Button { Task { await loadMore() } } label: {
                    Text(L10n.browse.loadMore)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Color.paper2))
                        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(L10n.browse.endOfFeed(items.count))
                    .font(.mono11).tracking(0.5).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // ── Toolbar: chips (left, scrollable) + filter dropdown + size ──
    private var toolbar: some View {
        // One row: [All (pinned)] [scrollable categories] … [filter][size].
        // The category strip is bounded to the available width by the
        // ScrollView, so it can't push the page wider than the window
        // (which was eating the right margin in windowed mode). When the
        // categories all fit (e.g. full-screen), the strip just doesn't
        // scroll. "All" stays pinned at the front, outside the scroll.
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                categoryChip(label: L10n.browse.chipAll, id: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { c in
                            categoryChip(label: c.name, id: c.id)
                        }
                    }
                    .padding(.vertical, 2)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ChipsContentWidthKey.self, value: g.size.width)
                    })
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: ChipsViewportWidthKey.self, value: g.size.width)
                })
                .onPreferenceChange(ChipsContentWidthKey.self) { chipsContentW = $0 }
                .onPreferenceChange(ChipsViewportWidthKey.self) { chipsViewportW = $0 }
                // Trailing fade — only when the chips overflow the strip.
                // The gradient fades the last ~28pt to transparent so the
                // hidden categories read as "scroll for more"; when they
                // all fit it's a flat mask (no fade).
                .mask(
                    LinearGradient(
                        stops: chipsOverflow
                            ? [.init(color: .black, location: 0),
                               .init(color: .black, location: chipsFadeStart),
                               .init(color: .clear, location: 1)]
                            : [.init(color: .black, location: 0),
                               .init(color: .black, location: 1)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            filterMenu
            sizeControl
        }
        // Sit above the device banner / feed so nothing layered below can
        // intercept the chip taps.
        .zIndex(1)
    }

    private func categoryChip(label: String, id: Int?) -> some View {
        let active = selectedCategoryID == id
        return Button { selectedCategoryID = id } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.paper : Color.ink2)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(active ? Color.ink : Color.chromeControl))
                .overlay(Capsule().stroke(active ? Color.ink : ChromeLine.softBorder(for: palette), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // FILTER dropdown — matches the web's labelled dropdown.
    private var filterMenu: some View {
        Menu {
            ForEach(availableFilters, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    if filter == f {
                        Label(f.label, systemImage: "checkmark")
                    } else {
                        Text(f.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(L10n.browse.filterKicker)
                    .font(.mono10).tracking(1.2).foregroundStyle(Color.muted)
                Text(filter.label)
                    .font(.sans12).foregroundStyle(Color.ink2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.chromeControl))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ChromeLine.softBorder(for: palette), lineWidth: 1))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    // LG / MD size segmented control — matches the web's SizeControls.
    private var sizeControl: some View {
        HStack(spacing: 2) {
            ForEach([SizeMode.md, .lg], id: \.self) { s in
                let on = sizeMode == s
                Button(action: { sizeMode = s }) {
                    Text(s.rawValue)
                        .font(.system(size: 11, weight: on ? .semibold : .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(on ? Color.paper : Color.muted)
                        .frame(minWidth: 30, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? Color.ink : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.chromeControl))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ChromeLine.softBorder(for: palette), lineWidth: 1))
        .fixedSize()
    }

    private func errorBanner(_ msg: String) -> some View {
        RemoteLoadErrorView(message: msg) {
            Task { await reload() }
        }
    }

    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false; loadError = nil; featuredHover = nil
        loading = true
        defer { loading = false }
        if filter == .forYou {
            await loadForYouPage()
        } else {
            await loadWallpaperPage()
        }
    }

    // For You is a single-shot top-N feed. On empty (cold-start users)
    // fall back to Latest so the page still shows content — the filter
    // change re-triggers reload via onChange.
    private func loadForYouPage() async {
        do {
            let list = try await APIClient.shared.fetchForYou(limit: 30)
            if list.isEmpty {
                filter = .latest
                return
            }
            items = list
            cursor = nil
            hasMore = false
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        await loadWallpaperPage()
    }

    private func loadWallpaperPage() async {
        do {
            let data = try await APIClient.shared.fetchWallpapers(
                cursor: cursor,
                limit: 24,
                dynamicOnly: filter == .live,
                aiOnly: filter == .ai,
                search: search.isEmpty ? nil : search,
                categoryID: selectedCategoryID,
                sort: filter == .trending ? "trending" : nil,
                deviceMatch: filter == .myDevice,
                // Discover mirrors the web: Latest / Trending / Search /
                // Category should include video wallpapers too. Live still
                // narrows the feed with dynamic_only, which server-side
                // means Mac dynamic wallpapers ∪ video wallpapers.
                includeVideo: true
            )
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Width probes for the category strip: the inner HStack reports its
// intrinsic content width, the ScrollView its visible width. When the
// former exceeds the latter the strip overflows and the trailing fade
// turns on.
private struct ChipsContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct ChipsViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
