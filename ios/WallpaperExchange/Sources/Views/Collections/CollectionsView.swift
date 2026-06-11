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
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
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

struct CollectionCard: View {
    let collection: CollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tileStrip
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.display18)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text("\(collection.wallpaperCount) WALLPAPERS")
                        .font(.mono10)
                        .tracking(0.8)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                if let likes = collection.likeCount, likes > 0 {
                    Label("\(likes)", systemImage: "heart")
                        .font(.mono10)
                        .foregroundStyle(Color.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .paperCard(radius: 14)
    }

    // Up to three recent tiles side by side; accent-color fill when the
    // collection has no rendered tiles yet.
    private var tileStrip: some View {
        HStack(spacing: 2) {
            let tiles = collection.recentTiles ?? []
            if tiles.isEmpty {
                Rectangle()
                    .fill(Color(hex: collection.accentColor) ?? Color.paper3)
            } else {
                ForEach(Array(tiles.prefix(3).enumerated()), id: \.offset) { _, tile in
                    CachedAsyncImage(url: URL(string: tile.thumbURL), maxPixelDimension: 500) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color(hex: tile.dominantColor) ?? Color.paper3)
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
        .background(Color.paper)
        .navigationTitle(collection.title)
        .inlineNavTitle()
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
