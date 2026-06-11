import SwiftUI

// Public community collections, paged. Tapping opens the collection's
// wallpapers as a paged grid.
struct CollectionsView: View {
    @State private var collections: [CollectionItem] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let loadError, collections.isEmpty {
                        ErrorRetryView(message: loadError) { loadNextPage() }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(collections) { collection in
                                NavigationLink(value: collection) {
                                    CollectionCard(collection: collection)
                                }
                                .buttonStyle(.plain)
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
            .navigationTitle("Collections")
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

struct CollectionCard: View {
    let collection: CollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tileStrip
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(collection.wallpaperCount) wallpapers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let likes = collection.likeCount, likes > 0 {
                    Label("\(likes)", systemImage: "heart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // Up to three recent tiles side by side; accent-color fill when the
    // collection has no rendered tiles yet.
    private var tileStrip: some View {
        HStack(spacing: 2) {
            let tiles = collection.recentTiles ?? []
            if tiles.isEmpty {
                Rectangle()
                    .fill(Color(hex: collection.accentColor) ?? Color(.systemGray5))
            } else {
                ForEach(Array(tiles.prefix(3).enumerated()), id: \.offset) { _, tile in
                    CachedAsyncImage(url: URL(string: tile.thumbURL), maxPixelDimension: 500) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color(hex: tile.dominantColor) ?? Color(.systemGray5))
                    }
                    .clipped()
                }
            }
        }
        .frame(height: 110)
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
                } else {
                    WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) { loadNextPage() }
                    if loading { LoadingFooter() }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
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
