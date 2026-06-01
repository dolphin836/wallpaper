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

// Mirrors the web's editorial CollectionCard: a 3-photo stacked
// composition (1 large main on the left, 2 smaller subs stacked on
// the right) above a hairline rule and a mono № line + display title.
// "+N" badge appears on the third sub when the collection has more
// than 3 wallpapers.
struct CollectionCard: View {
    let item: CollectionItem
    @State private var hover = false

    private var tiles: [CollectionTile] {
        item.recentTiles ?? []
    }
    private var main: CollectionTile? { tiles.first }
    private var sub1: CollectionTile? { tiles.count > 1 ? tiles[1] : nil }
    private var sub2: CollectionTile? { tiles.count > 2 ? tiles[2] : nil }
    private var extra: Int { max(0, item.wallpaperCount - 3) }
    private var idStr: String { String(format: "№%03d", item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 3-photo stack. Main: ~2/3 width on the left. Subs: 1/3
            // width stacked on the right. 1pt hairline gaps between
            // slots; entire stack clipped to a single rounded corner.
            HStack(spacing: 1) {
                stackTile(main, isMain: true)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 1) {
                    stackTile(sub1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ZStack(alignment: .topTrailing) {
                        stackTile(sub2)
                        if extra > 0 {
                            Text("+\(extra)")
                                .font(.mono10).tracking(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                                .padding(6)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 80)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
            .scaleEffect(hover ? 1.005 : 1.0)
            .shadow(color: Color.black.opacity(hover ? 0.12 : 0.04),
                    radius: hover ? 14 : 6, x: 0, y: hover ? 6 : 2)

            // Hairline rule + caption. Hairline wipes to accent on hover
            // (a thin overlay scaled in X from leading) for the web's
            // signature "underline wipe" interaction.
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.hair).frame(height: 1)
                Rectangle().fill(Color.accent).frame(height: 1)
                    .scaleEffect(x: hover ? 1 : 0, y: 1, anchor: .leading)
                    .animation(.easeOut(duration: 0.3), value: hover)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(idStr) · \(item.wallpaperCount) \(item.wallpaperCount == 1 ? "WALLPAPER" : "WALLPAPERS")")
                    .font(.kicker).tracking(1.4).foregroundStyle(Color.muted)
                Text(item.title)
                    .font(.displayMd)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            .padding(.top, 10)
        }
        .animation(.easeOut(duration: 0.2), value: hover)
        .onHover { hover = $0 }
    }

    @ViewBuilder
    private func stackTile(_ tile: CollectionTile?, isMain: Bool = false) -> some View {
        let cornerGuide = isMain ? 14 : 6
        ZStack {
            if let t = tile {
                Color(hex: t.dominantColor).opacity(0.5)
                CachedAsyncImage(url: URL(string: t.previewURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            } else if isMain, let cover = item.coverURL, !cover.isEmpty {
                CachedAsyncImage(url: URL(string: cover)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.paper2
                }
            } else {
                Color.paper2
            }
        }
        .clipped()
        // The outer clipShape already rounds the stack as a whole; we
        // don't round individual slots so the hairline gaps look like
        // a single composed surface, not three pills.
        .contentShape(Rectangle())
        .accessibilityHidden(cornerGuide < 0)
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
