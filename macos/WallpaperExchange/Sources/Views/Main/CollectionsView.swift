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

// Mirrors web's .h3-tile-collection — the "stacked paper" tile used
// on HomePage Collections row and the /collections grid.
//   • aspect-ratio: 1/1
//   • border-radius: 14
//   • cover image fills the frame, scale 1.04 on hover
//   • two stacked paper layers behind the card (4px / 8px offsets at
//     rest, 6/12 on hover) give the editorial "stack of prints" look
//   • bottom gradient (transparent 40% → rgba(0,0,0,0.7))
//   • white copy bottom-left: display title 18, mono count 10 caps
struct CollectionCard: View {
    let item: CollectionItem
    @State private var hover = false
    @State private var imgLoaded = false

    // First recent tile preview if available, else the saved cover_url.
    private var imageURL: URL? {
        if let t = item.recentTiles?.first {
            return URL(string: t.previewURL)
        }
        if let cover = item.coverURL, !cover.isEmpty {
            return URL(string: cover)
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ─── Back paper layer 2 (furthest) ─────────────────────
            // Web: 8px 8px 0 0 oklch(82% 0.012 240) — slightly cooler
            // gray. On hover translates to 12,12 to fan out.
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.81, green: 0.81, blue: 0.83))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: hover ? 12 : 8, y: hover ? 12 : 8)

            // ─── Back paper layer 1 ───────────────────────────────
            // Web: 4px 4px 0 0 oklch(86% 0.010 240) — lighter gray.
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.86, green: 0.86, blue: 0.87))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: hover ? 6 : 4, y: hover ? 6 : 4)

            // ─── Front card (image + gradient + copy) ─────────────
            ZStack(alignment: .bottomLeading) {
                Color.paper2

                if let url = imageURL {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(hex: item.recentTiles?.first?.dominantColor ?? "#bbb").opacity(0.5)
                    }
                    .scaleEffect(hover ? 1.04 : 1.0)
                    .opacity(imgLoaded ? 1 : 0.001)
                    .onAppear { imgLoaded = true }
                    .animation(.easeOut(duration: 0.4), value: imgLoaded)
                    .animation(.easeOut(duration: 0.8), value: hover)
                }

                // Gradient: linear-gradient(180deg, transparent 40%, rgba(0,0,0,0.7))
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.4),
                        .init(color: Color.black.opacity(0.7), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Copy: left/right/bottom 14
                VStack(alignment: .leading, spacing: 4) {
                    // .h3-title — display 18, weight 400, line-height 1.1
                    Text(item.title.isEmpty ? "Untitled set" : item.title)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.7), radius: 14, x: 0, y: 2)
                    // .h3-count — mono 10, letter-spacing 0.14em, caps
                    Text("\(item.wallpaperCount) WALLPAPERS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            )
            // Front-card lift on hover. Web: translate(-3px,-3px).
            .offset(x: hover ? -3 : 0, y: hover ? -3 : 0)
            .shadow(color: Color.black.opacity(hover ? 0.32 : 0.20),
                    radius: hover ? 30 : 18, x: 0, y: hover ? 14 : 8)
        }
        .aspectRatio(1.0, contentMode: .fit)
        // Reserve space for the offset paper layers so the card doesn't
        // clip into adjacent grid cells.
        .padding(.trailing, 12).padding(.bottom, 12)
        .animation(.easeOut(duration: 0.38), value: hover)
        .contentShape(Rectangle())
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
