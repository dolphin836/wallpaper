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
                                PagingFooter(isLoading: loading, hasMore: hasMore, showsEndState: false, onLoadMore: loadNextPage)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.top, showsTopBar ? 8 : 8)
                }
                .background(Color.clear)
            }
            .background(PageMesh())
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .navigationDestination(for: CollectionItem.self) { collection in
                CollectionDetailView(collection: collection)
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
        .paletteReactive(palette: nil, dominant: cover?.dominantColor ?? collection.accentColor)
    }

    private var collectionMosaic: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.20))
            GeometryReader { proxy in
                let inset: CGFloat = 5
                let gap: CGFloat = 5
                let contentWidth = max(0, proxy.size.width - inset * 2)
                let contentHeight = max(0, proxy.size.height - inset * 2)
                let mainWidth = max(0, (contentWidth - gap) * 0.62)
                let sideWidth = max(0, contentWidth - gap - mainWidth)
                let sideHeight = max(0, (contentHeight - gap) / 2)

                ZStack(alignment: .topLeading) {
                    mosaicImage(tiles.indices.contains(0) ? tiles[0] : nil)
                        .frame(width: mainWidth, height: contentHeight)
                        .offset(x: inset, y: inset)
                    mosaicImage(tiles.indices.contains(1) ? tiles[1] : nil)
                        .frame(width: sideWidth, height: sideHeight)
                        .offset(x: inset + mainWidth + gap, y: inset)
                    mosaicImage(tiles.indices.contains(2) ? tiles[2] : nil)
                        .frame(width: sideWidth, height: sideHeight)
                        .offset(x: inset + mainWidth + gap, y: inset + sideHeight + gap)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.hair.opacity(0.7), lineWidth: 1)
        )
    }

    private func mosaicImage(_ tile: CollectionTile?) -> some View {
        Color.clear
            .overlay {
                ProgressiveCollectionMosaicImage(
                    tile: tile,
                    fallbackTile: cover,
                    coverURL: collection.coverURL,
                    accent: accent
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()
    }

    private var metaLine: String {
        let s = L10n.strings(for: UIPrefs.shared.language)
        var line = String(format: s.wallpapersCount, collection.wallpaperCount)
        if let likes = collection.likeCount, likes > 0 {
            line += " · \(likes) \(s.likeStat)"
        }
        return line
    }
}

private struct ProgressiveCollectionMosaicImage: View {
    let tile: CollectionTile?
    let fallbackTile: CollectionTile?
    let coverURL: String?
    let accent: Color

    @State private var lowLoaded = false
    @State private var highLoaded = false
    @State private var shouldLoadHigh = false
    @State private var highCandidateIndex = 0
    @State private var lowCanSettle = false
    @State private var loadingFailed = false

    private var lowURL: URL? {
        normalizedURL(tile?.thumbURL) ?? (tile == nil ? normalizedURL(fallbackTile?.thumbURL) : nil)
    }

    private var highCandidates: [URL] {
        var candidates: [URL] = []
        let low = lowURL

        func appendCandidate(_ value: String?) {
            guard let url = normalizedURL(value), url != low, !candidates.contains(url) else { return }
            candidates.append(url)
        }

        if tile != nil {
            appendCandidate(tile?.previewURL)
            appendCandidate(tile?.thumbURL)
        } else {
            appendCandidate(coverURL)
            appendCandidate(fallbackTile?.previewURL)
            appendCandidate(fallbackTile?.thumbURL)
        }

        return candidates
    }

    private var currentHighURL: URL? {
        let candidates = highCandidates
        guard candidates.indices.contains(highCandidateIndex) else { return nil }
        return candidates[highCandidateIndex]
    }

    private var dominantFill: Color {
        Color(hex: tile?.dominantColor ?? fallbackTile?.dominantColor) ?? accent
    }

    private var lowIsCached: Bool {
        guard let lowURL else { return false }
        return ImageCacheStore.shared.get(lowURL, maxPixelDimension: 320) != nil
    }

    private var currentHighIsCached: Bool {
        guard let currentHighURL else { return false }
        return ImageCacheStore.shared.get(currentHighURL, maxPixelDimension: 760) != nil
    }

    private var showsLoadingVeil: Bool {
        !highLoaded
            && !loadingFailed
            && !currentHighIsCached
            && (currentHighURL != nil || (lowURL != nil && !lowLoaded && !lowIsCached))
    }

    private var loadIdentity: String {
        [
            tile?.thumbURL ?? "",
            tile?.previewURL ?? "",
            fallbackTile?.thumbURL ?? "",
            fallbackTile?.previewURL ?? "",
            coverURL ?? "",
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            Rectangle().fill(dominantFill)

            if let lowURL {
                let lowIsFinal = currentHighURL == nil || lowCanSettle
                CachedAsyncImage(
                    url: lowURL,
                    maxPixelDimension: 320,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            lowLoaded = true
                            shouldLoadHigh = currentHighURL != nil
                        }
                    },
                    onFailure: {
                        shouldLoadHigh = currentHighURL != nil
                        if currentHighURL == nil {
                            lowCanSettle = true
                            loadingFailed = true
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: highLoaded || lowIsFinal ? 0 : 8)
                        .scaleEffect(highLoaded || lowIsFinal ? 1 : 1.06)
                        .opacity(highLoaded || currentHighIsCached ? 0 : 0.96)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if let currentHighURL, shouldLoadHigh || lowURL == nil || currentHighIsCached {
                CachedAsyncImage(
                    url: currentHighURL,
                    maxPixelDimension: 760,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            highLoaded = true
                        }
                    },
                    onFailure: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if highCandidateIndex + 1 < highCandidates.count {
                                highCandidateIndex += 1
                            } else {
                                lowCanSettle = true
                                loadingFailed = true
                            }
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if showsLoadingVeil {
                ImageLoadingVeil(strength: lowLoaded ? .whisper : .card)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: loadIdentity) {
            lowLoaded = false
            highLoaded = false
            highCandidateIndex = 0
            lowCanSettle = false
            loadingFailed = false
            shouldLoadHigh = lowURL == nil || currentHighIsCached
            if lowURL != nil {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                shouldLoadHigh = currentHighURL != nil
            }
        }
    }

    private func normalizedURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
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
                    WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore, isLoading: loading, showsEndState: false) { loadNextPage() }
                }
            }
            .padding(.top, 8)
        }
        .background(PageMesh())
        .navigationTitle(collection.title)
        .inlineNavTitle()
        .showNavBarCompat()
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                LockPreviewToolbarButton()
            }
            #endif
        }
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
