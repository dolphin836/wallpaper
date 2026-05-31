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

    enum Filter: String, CaseIterable, Hashable {
        case latest = "Latest"
        case trending = "Trending"
        case myDevice = "My Device"
        case dynamic = "Mac Dynamic"
        case ai = "AI"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
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
            await reload()
        }
        .onChange(of: filter) { _, _ in Task { await reload() } }
        .onChange(of: search) { _, _ in Task { await reload() } }
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
                dynamicOnly: filter == .dynamic,
                aiOnly: filter == .ai,
                search: search.isEmpty ? nil : search,
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
