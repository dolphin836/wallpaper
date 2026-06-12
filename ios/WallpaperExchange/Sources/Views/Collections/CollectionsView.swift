import SwiftUI

// Public community collections, paged — presented as the full-screen
// drawer behind the top toolbar's left button. Tapping a collection
// pushes its wallpapers as a paged grid.
struct CollectionsBrowser: View {
    @Environment(\.dismiss) private var dismiss

    @State private var collections: [CollectionItem] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        SectionHeader(kicker: "Curated by the community", title: "Collections")
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink2)
                                .frame(width: 32, height: 32)
                                .background(Color.paper2, in: Circle())
                                .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    if let loadError, collections.isEmpty {
                        ErrorRetryView(message: loadError) { loadNextPage() }
                    } else if collections.isEmpty && loading {
                        VStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonBlock(radius: 14).frame(height: 160)
                            }
                        }
                        .padding(.horizontal, 12)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(collections) { collection in
                                NavigationLink(value: collection) {
                                    CollectionCard(collection: collection)
                                }
                                .buttonStyle(.pressable)
                            }
                            if hasMore {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear { loadNextPage() }
                            }
                        }
                        .padding(.horizontal, 12)
                        if loading { LoadingFooter() }
                    }
                }
                .padding(.top, 8)
            }
            .background(Color.paper)
            .navigationTitle("")
            .inlineNavTitle()
            .navigationDestination(for: CollectionItem.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .navigationDestination(for: WallpaperRoute.self) { route in
                WallpaperDetailView(slug: route.slug)
            }
            .refreshable { await reload() }
            .task { if collections.isEmpty { loadNextPage() } }
        }
    }

    private func reload() async {
        collections = []
        cursor = nil
        hasMore = true
        loadError = nil
        loadNextPage()
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await APIClient.shared.fetchPublicCollections(cursor: cursor)
                collections.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
                loadError = nil
            } catch {
                if collections.isEmpty { loadError = error.localizedDescription }
                hasMore = false
            }
        }
    }
}

// Collection card: editorial mosaic cover (one dominant tile, two
// supporting) over a paper info row — serif title, accent-color dot
// echoing the collection's palette, mono-caps meta.
struct CollectionCard: View {
    let collection: CollectionItem

    private var tiles: [CollectionTile] {
        Array((collection.recentTiles ?? []).prefix(3))
    }

    private var accent: Color {
        Color(hex: collection.accentColor) ?? Color.paper3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mosaic
                .frame(height: 150)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.title)
                    .font(.display18)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                    Text(metaLine)
                        .font(.mono10)
                        .tracking(0.8)
                        .foregroundStyle(Color.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .paperCard(radius: 14)
        .shadow(color: .black.opacity(0.07), radius: 12, y: 6)
    }

    private var metaLine: String {
        var line = "\(collection.wallpaperCount) WALLPAPERS"
        if let likes = collection.likeCount, likes > 0 {
            line += " · \(likes) ♥"
        }
        return line
    }

    // 2/3 cover + two stacked tiles; degrades gracefully when the
    // collection has fewer rendered tiles.
    @ViewBuilder
    private var mosaic: some View {
        switch tiles.count {
        case 0:
            ZStack {
                accent.opacity(0.85)
                Text(String(collection.title.prefix(1)).uppercased())
                    .font(.system(size: 56, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.lightText.opacity(0.85))
            }
        case 1:
            mosaicTile(tiles[0], dimension: 900)
        default:
            GeometryReader { geo in
                HStack(spacing: 2) {
                    mosaicTile(tiles[0], dimension: 900)
                        .frame(width: geo.size.width * 0.62)
                    if tiles.count >= 3 {
                        VStack(spacing: 2) {
                            mosaicTile(tiles[1], dimension: 500)
                            mosaicTile(tiles[2], dimension: 500)
                        }
                    } else {
                        mosaicTile(tiles[1], dimension: 500)
                    }
                }
            }
        }
    }

    private func mosaicTile(_ tile: CollectionTile, dimension: Int) -> some View {
        Color.clear
            .overlay(
                CachedAsyncImage(
                    url: URL(string: dimension > 600 ? tile.previewURL : tile.thumbURL),
                    maxPixelDimension: dimension
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(hex: tile.dominantColor) ?? Color.paper3)
                }
            )
            .clipped()
    }
}

struct CollectionDetailView: View {
    let collection: CollectionItem

    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let description = collection.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                if let loadError, wallpapers.isEmpty {
                    ErrorRetryView(message: loadError) { loadNextPage() }
                } else if wallpapers.isEmpty && loading {
                    WallpaperGridSkeleton(count: 8)
                } else if wallpapers.isEmpty {
                    EmptyStateView(kicker: "Empty shelf", message: "This collection has no wallpapers yet.")
                } else {
                    WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) { loadNextPage() }
                    if loading { LoadingFooter() }
                }
            }
            .padding(.top, 8)
        }
        .background(Color.paper)
        .navigationTitle(collection.title)
        .inlineNavTitle()
        .showNavBarCompat()
        .task { if wallpapers.isEmpty { loadNextPage() } }
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await APIClient.shared.fetchCollectionWallpapers(collectionID: collection.id, cursor: cursor)
                wallpapers.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
                loadError = nil
            } catch {
                if wallpapers.isEmpty { loadError = error.localizedDescription }
                hasMore = false
            }
        }
    }
}
