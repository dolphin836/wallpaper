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

// Mirrors web's .h3-tile-collection — the "stacked paper" tile.
//
// Layout strategy (GeometryReader-bounded so the LazyVGrid cell math
// never breaks): the cell is a 1:1 square of size W×W. The card sits
// at the top-left at (W-12)×(W-12), with two paper layers offset 4 and
// 8 points into the reserved 12pt bottom-right margin. Everything
// stays strictly within the W×W cell — adjacent grid cells never
// overlap our content, no matter the hover state.
struct CollectionCard: View {
    let item: CollectionItem
    @State private var hover = false
    @State private var imgLoaded = false

    // Web HomePage CollectionTile uses `c.cover_url` exclusively —
    // recent_tiles is only used by the editorial CollectionCard
    // (in the /collections page). Match the web home tile here.
    private var imageURL: URL? {
        if let cover = item.coverURL, !cover.isEmpty {
            return URL(string: cover)
        }
        return nil
    }

    var body: some View {
        GeometryReader { geom in
            // Some columns get fractional widths; use min() to be safe.
            let cell = min(geom.size.width, geom.size.height)
            // Reserve 12pt at the bottom-right for the two paper layers.
            // Card itself stays (cell - 12) so the deepest paper edge
            // sits flush at the cell's bottom-right corner.
            let cardSize = max(0, cell - 12)

            ZStack(alignment: .topLeading) {
                // Paper 2 — furthest behind. Web uses oklch(82% 0.012 240)
                // which is barely-there light gray on the warm bg. Need
                // to match the subtle "stacked sheets" feel, not a
                // chunky offset rectangle.
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.89, green: 0.88, blue: 0.87))
                    .frame(width: cardSize, height: cardSize)
                    .offset(x: hover ? 12 : 8, y: hover ? 12 : 8)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)

                // Paper 1 — between paper 2 and the front card.
                // oklch(86% 0.010 240) — slightly lighter than paper 2.
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.92, green: 0.91, blue: 0.90))
                    .frame(width: cardSize, height: cardSize)
                    .offset(x: hover ? 6 : 4, y: hover ? 6 : 4)
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)

                // Front card
                frontCard
                    .frame(width: cardSize, height: cardSize)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                            .blendMode(.overlay)
                            .allowsHitTesting(false)
                    )
                    // Tiny lift on hover. Bounded so it doesn't
                    // overflow the cell top-left.
                    .offset(x: hover ? -2 : 0, y: hover ? -2 : 0)
                    .shadow(color: Color.black.opacity(hover ? 0.30 : 0.18),
                            radius: hover ? 22 : 12,
                            x: 0, y: hover ? 10 : 6)
            }
            // Lock the ZStack to the full cell so paper layers can't
            // bleed past geom bounds.
            .frame(width: cell, height: cell, alignment: .topLeading)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .animation(.easeOut(duration: 0.38), value: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    // ─── Front card content ────────────────────────────────────
    private var frontCard: some View {
        ZStack(alignment: .bottomLeading) {
            Color.paper2

            if let url = imageURL {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.paper2
                }
                .scaleEffect(hover ? 1.04 : 1.0)
                .opacity(imgLoaded ? 1 : 0.001)
                .onAppear { imgLoaded = true }
                .animation(.easeOut(duration: 0.4), value: imgLoaded)
                .animation(.easeOut(duration: 0.8), value: hover)
            }

            // Bottom gradient — transparent 40% → rgba(0,0,0,0.7)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.4),
                    .init(color: Color.black.opacity(0.7), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Copy — left/right/bottom 14.
            // CRITICAL: .frame(maxWidth: .infinity, alignment: .leading)
            // before .padding constrains the VStack to the card's width
            // so long titles wrap to 2 lines instead of overflowing and
            // getting center-clipped. Without this, ZStack expands to
            // fit the widest child (the long title), and the outer
            // .frame(cardSize) centers it, chopping equal amounts off
            // both sides of the text.
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? "Untitled set" : item.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.7), radius: 14, x: 0, y: 2)
                Text("\(item.wallpaperCount) WALLPAPERS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
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
