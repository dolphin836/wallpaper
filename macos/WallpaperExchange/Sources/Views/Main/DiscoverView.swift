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
    @State private var loading = false
    @State private var loadError: String?
    @State private var filter: Filter = .latest
    @State private var sizeMode: SizeMode = .lg
    // The wallpaper currently shown on the device mockup. Driven by
    // hovering grid tiles (web "floating wall" feel); falls back to the
    // first feed item.
    @State private var featuredHover: Wallpaper?
    @State private var categories: [Category] = []
    @State private var selectedCategoryID: Int? = nil

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

    private var gridColumns: [GridItem] {
        switch sizeMode {
        case .lg: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14, alignment: .top)]
        case .md: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12, alignment: .top)]
        }
    }

    var body: some View {
        // Everything lives in ONE vertical ScrollView so a scroll
        // gesture anywhere in the content moves the page. The toolbar +
        // device mockup are a PINNED section header so they stay fixed
        // at the top (always previewing the hovered tile) while the grid
        // scrolls underneath — scrolling over the header still drives
        // the feed because the header is part of the same ScrollView.
        GeometryReader { geo in
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    feed
                        .padding(.horizontal, 40)
                        .padding(.top, 14)
                        .padding(.bottom, 40)
                } header: {
                    VStack(alignment: .leading, spacing: 14) {
                        toolbar

                        if let shown = featuredHover ?? items.first {
                            DevicePreviewBanner(featured: shown, onPick: { onPick(shown) })
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Re-draw the page floor (paper + the SAME mesh, sized
                    // to the full pane and top-anchored) behind the pinned
                    // header so wallpapers scrolling up behind it stay
                    // hidden and the header reads as the exact same
                    // background as the rest of the page — not a white band,
                    // not the tiles showing through.
                    .background(alignment: .top) {
                        ZStack {
                            Color.paper
                            PageMesh()
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        // Never let the oversized floor intercept events —
                        // otherwise its hit region covers the grid below the
                        // pinned header and swallows tile hover (which drives
                        // the device preview + page mesh + card action rail).
                        .allowsHitTesting(false)
                    }
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    // ── Feed: the scrolling grid + loading / empty / error states.
    // Hovering a tile lifts it into the pinned device mockup above. ──
    @ViewBuilder
    private var feed: some View {
        if loading && items.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, 60)
        } else if let err = loadError, items.isEmpty {
            errorBanner(err)
        } else if items.isEmpty {
            Text(search.isEmpty ? "No wallpapers." : "No wallpapers match.")
                .font(.sans13).foregroundStyle(Color.muted).padding(.top, 20)
        } else {
            LazyVGrid(columns: gridColumns, spacing: sizeMode == .lg ? 14 : 12) {
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

    // Infinite-scroll footer — loading spinner, a manual "Load more"
    // fallback, a retry on pagination error, and an end-of-feed marker.
    // Mirrors the web's FeedFooter vocabulary.
    @ViewBuilder
    private var feedFooter: some View {
        Group {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading more…").font(.sans12).foregroundStyle(Color.muted)
                }
            } else if loadError != nil {
                HStack(spacing: 10) {
                    Text("Couldn't load more").font(.sans12).foregroundStyle(Color.ink2)
                    Button("Retry") { Task { await loadMore() } }.controlSize(.small)
                }
            } else if hasMore {
                Button { Task { await loadMore() } } label: {
                    Text("Load more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Color.paper2))
                        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("\(items.count) wallpaper\(items.count == 1 ? "" : "s") · You've reached the end")
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
                categoryChip(label: "All", id: nil)
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
                .background(Capsule().fill(active ? Color.ink : Color.paper))
                .overlay(Capsule().stroke(active ? Color.ink : Color.hair, lineWidth: 1))
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
                        Label(f.rawValue, systemImage: "checkmark")
                    } else {
                        Text(f.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("FILTER")
                    .font(.mono10).tracking(1.2).foregroundStyle(Color.muted)
                Text(filter.rawValue)
                    .font(.sans12).foregroundStyle(Color.ink2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.paper2))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hair, lineWidth: 1))
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.paper2))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hair, lineWidth: 1))
        .fixedSize()
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11)).foregroundStyle(Color.warn)
            Text(msg).font(.sans11).foregroundStyle(Color.ink2).lineLimit(2)
            Spacer()
            Button("Retry") { Task { await reload() } }.controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.warn.opacity(0.06)))
    }

    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false; loadError = nil; featuredHover = nil
        if filter == .forYou {
            await loadForYou()
        } else {
            await loadMore()
        }
    }

    // For You is a single-shot top-N feed. On empty (cold-start users)
    // fall back to Latest so the page still shows content — the filter
    // change re-triggers reload via onChange.
    private func loadForYou() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
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
                // Live = Mac dynamic ∪ video (dynamic_only spans both
                // server-side); opt video back in for this filter.
                includeVideo: filter == .live
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
