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

// Collection card, reference topic style: one full-bleed cover, bottom
// gradient scrim, bold title with a quiet count beneath.
struct CollectionCard: View {
    let collection: CollectionItem
    var height: CGFloat = 190

    private var cover: CollectionTile? { collection.recentTiles?.first }

    private var accent: Color {
        Color(hex: collection.accentColor) ?? Color.paper3
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay(
                    CachedAsyncImage(
                        url: URL(string: cover?.previewURL ?? ""),
                        maxPixelDimension: 1100
                    ) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color(hex: cover?.dominantColor) ?? accent)
                    }
                )
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.05), .black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
    }

    private var metaLine: String {
        var line = "\(collection.wallpaperCount) wallpapers"
        if let likes = collection.likeCount, likes > 0 {
            line += " · \(likes) likes"
        }
        return line
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
