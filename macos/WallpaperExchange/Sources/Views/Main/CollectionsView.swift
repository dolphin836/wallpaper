import SwiftUI

// Public collections list. Loads /collections (cursor-paginated) and
// renders cards with a 2×2 cover composition built from recent_tiles.
struct CollectionsListView: View {
    @State private var items: [CollectionItem] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Curated lists · yours and the community's")
                    Text("Collections").font(.display32).foregroundStyle(Color.ink)
                }

                if loading && items.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if let err = loadError {
                    Text(err).font(.sans12).foregroundStyle(Color.warn).padding(.top, 24)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 18, alignment: .top)], spacing: 18) {
                        ForEach(items) { c in
                            NavigationLink(value: MainWindow.MainRoute.collection(slug: c.slug, title: c.title)) {
                                CollectionCard(item: c)
                            }
                            .buttonStyle(.plain)
                            .onAppear { maybeLoadMore(c) }
                        }
                    }
                    if hasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
                            .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await reload() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false; loadError = nil
        await loadMore()
    }
    private func loadMore() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let data = try await APIClient.shared.fetchPublicCollections(cursor: cursor, limit: 24)
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
    private func maybeLoadMore(_ c: CollectionItem) {
        guard hasMore, !loading, let last = items.last, c.id == last.id else { return }
        Task { await loadMore() }
    }
}

struct CollectionCard: View {
    let item: CollectionItem
    @State private var hover = false

    private var tiles: [CollectionTile] {
        item.recentTiles ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 2×2 cover composition. Fall back to cover_url or a dominant-
            // color placeholder when recent_tiles is empty.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    if i < tiles.count {
                        CachedAsyncImage(url: URL(string: tiles[i].previewURL)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(hex: tiles[i].dominantColor).opacity(0.5)
                        }
                        .frame(height: 80).frame(maxWidth: .infinity).clipped()
                    } else if i == 0, let cover = item.coverURL, !cover.isEmpty {
                        CachedAsyncImage(url: URL(string: cover)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.paper2
                        }
                        .frame(height: 80).frame(maxWidth: .infinity).clipped()
                    } else {
                        Color.paper2.frame(height: 80)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.displayMd).foregroundStyle(Color.ink).lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(item.wallpaperCount) WALLPAPERS")
                        .font(.kicker).tracking(1.5).foregroundStyle(Color.muted)
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover ? Color.paper : Color.clear))
        .scaleEffect(hover ? 1.01 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.08 : 0), radius: 10, x: 0, y: 4)
        .animation(.easeOut(duration: 0.18), value: hover)
        .onHover { hover = $0 }
    }
}

// Collection detail — hero header + grid of wallpapers.
struct CollectionDetailView: View {
    let slug: String
    var onWallpaper: (Wallpaper) -> Void

    @State private var info: CollectionItem?
    @State private var items: [Wallpaper] = []
    @State private var loading = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if let c = info {
                    header(c)
                }
                if loading && items.isEmpty {
                    ProgressView()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(items) { wp in
                            Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        // page-mesh shows through; no opaque paper background here
        .task(id: slug) { await load() }
    }

    private func header(_ c: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "Collection №\(c.id) · \(c.wallpaperCount) wallpapers")
            Text(c.title).font(.display32).foregroundStyle(Color.ink)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let c = try await APIClient.shared.fetchCollection(slug: slug)
            info = c
            let data = try await APIClient.shared.fetchCollectionWallpapers(collectionID: c.id, limit: 36)
            items = data.items
        } catch {}
    }
}
