import SwiftUI

// Main Discover content — minimal editorial chrome to match the web's
// Discover page, just a kicker + filter pills + grid. No marketing
// headline. Filter pills dispatch to the right query parameters
// (sort=trending, dynamic_only, ai_only, device_width/height, etc.).
struct DiscoverView: View {
    let search: String
    var onPick: (Wallpaper) -> Void
    /// When true (used by the legacy device-match sidebar entry) the
    /// initial filter is forced to .myDevice. Discover itself starts on
    /// Latest.
    var deviceMatch: Bool = false

    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var filter: Filter = .latest
    @State private var categories: [Category] = []
    @State private var selectedCategoryID: Int? = nil

    enum Filter: String, CaseIterable, Hashable {
        case latest = "Latest"
        case trending = "Trending"
        case myDevice = "My Device"
        case live = "Live"
        case ai = "AI"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Static MacBook chassis at the top — mirrors the web's
                // device floating wall (without the orbiting animation).
                // Picks the first wallpaper of the feed as the featured
                // screen content; tapping the chassis opens that
                // wallpaper's detail page.
                if let first = items.first {
                    DevicePreviewBanner(featured: first, onPick: { onPick(first) })
                }
                categoryRow
                filterRow

                if loading && items.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.top, 60)
                } else if let err = loadError {
                    errorBanner(err)
                } else if items.isEmpty {
                    Text(search.isEmpty ? "No wallpapers." : "No wallpapers match.")
                        .font(.sans13).foregroundStyle(Color.muted).padding(.top, 20)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .top)],
                        spacing: 12
                    ) {
                        ForEach(items) { wp in
                            Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                                .onAppear { maybeLoadMore(wp) }
                        }
                    }
                    if hasMore {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small).opacity(loading ? 1 : 0)
                            Spacer()
                        }
                        .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .task(id: "discover-init") {
            if deviceMatch { filter = .myDevice }
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

    // Category chip row — All + each category. Matches the web's
    // .tile-chip family + active = ink/paper inverse.
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(label: "All", id: nil)
                ForEach(categories) { c in
                    categoryChip(label: c.name, id: c.id)
                }
            }
        }
    }

    private func categoryChip(label: String, id: Int?) -> some View {
        let active = selectedCategoryID == id
        return Button(action: { selectedCategoryID = id }) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.paper : Color.ink2)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(active ? Color.ink : Color.paper))
                .overlay(Capsule().stroke(active ? Color.ink : Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let isOn = filter == f
                Button(action: { filter = f }) {
                    Text(f.rawValue)
                        .font(.sans12)
                        .foregroundStyle(isOn ? Color.paper : Color.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(isOn ? Color.ink : Color.paper2))
                        .overlay(Capsule().stroke(Color.hair, lineWidth: isOn ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Total count chip on the right.
            if !items.isEmpty {
                Text("\(items.count) shown")
                    .font(.mono10).tracking(0.6).foregroundStyle(Color.muted)
            }
        }
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
        items = []; cursor = nil; hasMore = false; loadError = nil
        await loadMore()
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
                deviceMatch: filter == .myDevice
            )
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
}
