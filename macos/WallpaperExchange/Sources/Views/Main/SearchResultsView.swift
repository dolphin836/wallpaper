import SwiftUI

// Search results page. Calls fetchWallpapers with the `search` param —
// same plumbing the web uses. Pushed onto the nav stack from
// TopNavBar's submit action.
struct SearchResultsView: View {
    let query: String
    var onWallpaper: (Wallpaper) -> Void

    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 14, alignment: .top)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Search results")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\"\(query)\"")
                            .font(.display24).foregroundStyle(Color.ink)
                        Text("\(items.count) match\(items.count == 1 ? "" : "es")")
                            .font(.mono11).tracking(0.5).foregroundStyle(Color.muted)
                    }
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }

                if loading && items.isEmpty {
                    WallpaperGridSkeleton(columns: gridColumns, count: 12)
                } else if let err = loadError, items.isEmpty {
                    RemoteLoadErrorView(message: err) {
                        Task { await reload() }
                    }
                } else if items.isEmpty {
                    RemoteEmptyStateView(
                        title: "No wallpapers match.",
                        message: "Try a broader search term or browse Discover for nearby styles.",
                        symbol: "magnifyingglass"
                    )
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(items) { wp in
                            Button(action: { onWallpaper(wp) }) {
                                MainGridTile(wallpaper: wp)
                            }
                            .buttonStyle(.plain)
                            .onAppear { maybeLoadMore(wp) }
                        }
                    }
                    if let loadError {
                        HStack(spacing: 10) {
                            Text(loadError).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                            Button("Retry") { Task { await loadMore() } }.controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    } else if hasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
                            .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        // page-mesh shows through; no opaque paper background here
        .task(id: query) { await reload() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false
        loadError = nil
        await loadMore()
    }
    private func loadMore() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data = try await APIClient.shared.fetchWallpapers(cursor: cursor, limit: 24, search: query)
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }
}
