import SwiftUI

struct CollectionsTabView: View {
    var body: some View {
        CollectionsBrowser(showsDismissButton: false, showsTopBar: true, showsFloatingTabBar: true)
    }
}

// Public community collections, paged — presented as the full-screen
// drawer behind the top toolbar's left button. Tapping a collection
// pushes its wallpapers as a paged grid.
struct CollectionsBrowser: View {
    var showsDismissButton = true
    var showsTopBar = false
    var showsFloatingTabBar = false

    @Environment(\.dismiss) private var dismiss
    @Environment(UIPrefs.self) private var prefs

    @State private var collections: [CollectionItem] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsTopBar {
                    ArchiveTopBar(title: L10n.strings(for: prefs.language).collections)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            SectionHeader(
                                kicker: L10n.strings(for: prefs.language).collectionListKicker,
                                title: L10n.strings(for: prefs.language).collectionListTitle
                            )
                            Spacer()
                            if showsDismissButton {
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
                    .padding(.top, showsTopBar ? 8 : 8)
                }
                .background(Color.paper)
            }
            .background(Color.paper)
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .navigationDestination(for: CollectionItem.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .navigationDestination(for: WallpaperRoute.self) { route in
                WallpaperDetailView(slug: route.slug)
            }
            .refreshable { await reload() }
            .task { if collections.isEmpty { loadNextPage() } }
            .safeAreaInset(edge: .bottom) {
                if showsFloatingTabBar { FloatingTabBar() }
            }
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

// Collection card: a compact shelf/collage surface. It deliberately
// differs from Weekly's single-cover issue cards.
struct CollectionCard: View {
    let collection: CollectionItem
    var height: CGFloat = 190

    private var tiles: [CollectionTile] { collection.recentTiles ?? [] }
    private var cover: CollectionTile? { tiles.first }

    private var accent: Color {
        Color(hex: collection.accentColor) ?? Color.paper3
    }

    var body: some View {
        HStack(spacing: 12) {
            collectionMosaic
                .frame(width: max(112, height * 0.72), height: height - 22)

            VStack(alignment: .leading, spacing: 8) {
                Kicker(text: collection.kind == 1 ? "Theme" : "Shelf", tint: Color.muted)
                Text(collection.title)
                    .font(.system(size: height > 170 ? 22 : 18, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack")
                    Text("\(collection.wallpaperCount)")
                        .contentTransition(.numericText())
                    if let likes = collection.likeCount, likes > 0 {
                        Image(systemName: "heart")
                            .padding(.leading, 4)
                        Text("\(likes)")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(height: height)
        .background(Color.paper2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.hair, lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.12), radius: 14, y: 7)
    }

    private var collectionMosaic: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.20))
            HStack(spacing: 5) {
                mosaicImage(tiles.indices.contains(0) ? tiles[0] : nil)
                VStack(spacing: 5) {
                    mosaicImage(tiles.indices.contains(1) ? tiles[1] : nil)
                    mosaicImage(tiles.indices.contains(2) ? tiles[2] : nil)
                }
            }
            .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.hair.opacity(0.7), lineWidth: 1)
        )
    }

    private func mosaicImage(_ tile: CollectionTile?) -> some View {
        Color.clear
            .overlay(
                CachedAsyncImage(
                    url: URL(string: tile?.previewURL ?? cover?.previewURL ?? ""),
                    maxPixelDimension: 420
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(hex: tile?.dominantColor ?? cover?.dominantColor) ?? accent)
                }
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var metaLine: String {
        let s = L10n.strings(for: UIPrefs.shared.language)
        var line = String(format: s.wallpapersCount, collection.wallpaperCount)
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
                    EmptyStateView(kicker: "Empty shelf", message: L10n.strings(for: UIPrefs.shared.language).emptyCollection)
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
