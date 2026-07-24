import SwiftUI
import AppKit

// Shared by the public catalogue and the account's "My Collections" tab so
// their cards, skeletons, and four-row request size stay on one grid contract.
func collectionListColumnCount(for availableWidth: CGFloat) -> Int {
    availableWidth > 1180 ? 3 : (availableWidth > 720 ? 2 : 1)
}

func collectionListGridColumns(for availableWidth: CGFloat) -> [GridItem] {
    Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 24, alignment: .top),
        count: collectionListColumnCount(for: availableWidth)
    )
}

func collectionListPageSize(for availableWidth: CGFloat, rows: Int = 4) -> Int {
    collectionListColumnCount(for: availableWidth) * rows
}

// Public collections list. Loads /collections (cursor-paginated) and
// mirrors the web catalogue's compact stepped-cover card grid.
struct CollectionsListView: View {
    var onCollection: (CollectionItem) -> Void = { _ in }

    @State private var auth = AuthService.shared
    @State private var items: [CollectionItem] = []
    @State private var page = 0
    // Cursor needed to fetch each page (index 0 = first page = nil).
    @State private var pageCursors: [Int?] = [nil]
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var filter: Filter = .all
    @State private var showCreate = false

    enum Filter { case all, yours }
    private let pageSize = 12

    private var visible: [CollectionItem] {
        guard filter == .yours, let uid = auth.user?.id else { return items }
        return items.filter { $0.userID == uid }
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - 80)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if loading && items.isEmpty {
                        listSkeleton(availableWidth: contentWidth).padding(.top, 28)
                    } else if let err = loadError, items.isEmpty {
                        RemoteLoadErrorView(message: err) {
                            Task { await reload() }
                        }
                    } else if visible.isEmpty {
                        RemoteEmptyStateView(
                            title: filter == .yours ? L10n.collections.emptyYoursTitle : L10n.collections.emptyAllTitle,
                            message: filter == .yours
                                ? L10n.collections.emptyYoursMessage
                                : L10n.collections.emptyAllMessage,
                            symbol: "square.grid.2x2",
                            actionTitle: filter == .yours && auth.isLoggedIn ? L10n.collections.newCollection : nil,
                            action: filter == .yours && auth.isLoggedIn ? { showCreate = true } : nil
                        )
                    } else {
                        // Match the web catalogue: one consistent compact card
                        // grid, without a special first-page hero treatment.
                        LazyVGrid(columns: collectionListGridColumns(for: contentWidth), spacing: 24) {
                            ForEach(visible) { c in
                                Button(action: { onCollection(c) }) {
                                    CollectionListCard(item: c)
                                }
                                .buttonStyle(.plain)
                                .pointerCursor()
                            }
                        }
                        .padding(.top, 28)
                        pagination.padding(.top, 28)
                    }
                }
                .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .task { await reload() }
        .onChange(of: filter) { _, _ in Task { await reload() } }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
        .sheet(isPresented: $showCreate) {
            NewCollectionSheet(onCreated: { Task { await reload() } },
                               onClose: { showCreate = false })
        }
    }

    // Editorial header + All / Yours filter chips + New button.
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Kicker(text: L10n.collections.kicker)
                Text(L10n.collections.title).font(.display32).foregroundStyle(Color.ink)
                Text(L10n.collections.subtitle)
                    .font(.sans13).foregroundStyle(Color.ink2)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                filterChip(L10n.collections.filterAll, on: filter == .all) { filter = .all }
                if auth.isLoggedIn {
                    filterChip(L10n.collections.filterYours, on: filter == .yours) { filter = .yours }
                    GlassCapsuleButton(title: L10n.collections.newButton, icon: "plus", style: .accent, height: 30, fontSize: 12) {
                        showCreate = true
                    }
                }
            }
        }
    }

    // Prev / page / Next pagination (cursor-backed), mirroring the web.
    @ViewBuilder
    private var pagination: some View {
        HStack(spacing: 12) {
            Spacer()
            pageButton(L10n.collections.prevPage, enabled: page > 0 && !loading) {
                Task { await loadPage(page - 1) }
            }
            if loading {
                ProgressView().controlSize(.small).frame(width: 60)
            } else {
                Text(L10n.collections.pageLabel(page + 1))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.5).foregroundStyle(Color.ink2).frame(minWidth: 60)
            }
            pageButton(L10n.collections.nextPage, enabled: hasMore && !loading) {
                Task { await loadPage(page + 1) }
            }
            Spacer()
        }
    }

    private func listSkeleton(availableWidth: CGFloat) -> some View {
        LazyVGrid(columns: collectionListGridColumns(for: availableWidth), spacing: 24) {
            ForEach(0..<pageSize, id: \.self) { _ in
                CollectionListCardSkeleton()
            }
        }
    }

    private func pageButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        GlassCapsuleButton(title: label, height: 32, fontSize: 12, action: action)
            .disabled(!enabled)
    }

    private func filterChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        GlassChip(label: label, active: on, action: action)
    }

    private func reload() async {
        pageCursors = [nil]
        await loadPage(0)
    }

    private func loadPage(_ p: Int) async {
        guard !loading, p >= 0, p < pageCursors.count else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data = try await APIClient.shared.fetchPublicCollections(cursor: pageCursors[p], limit: pageSize)
            items = data.items
            hasMore = data.hasMore
            page = p
            // Record the cursor to fetch the *next* page (once).
            if data.hasMore, let next = data.nextCursor, p + 1 >= pageCursors.count {
                pageCursors.append(next)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Compact collection cards mirror the web c5 catalogue: a 16:10 three-image
// stepped cover above a fixed-height editorial copy block. Recent tiles keep
// the same dominant colour -> thumbnail -> preview loading sequence used by
// the rest of the Mac client.
private struct CollectionCoverSlot: Hashable {
    let thumbURL: URL?
    let previewURL: URL?
    let dominantColor: String?
}

private func collectionCoverSlots(_ item: CollectionItem) -> [CollectionCoverSlot] {
    var available = (item.recentTiles ?? []).map { tile in
        CollectionCoverSlot(
            thumbURL: tile.thumbURL.isEmpty ? nil : URL(string: tile.thumbURL),
            previewURL: tile.previewURL.isEmpty ? nil : URL(string: tile.previewURL),
            dominantColor: tile.dominantColor.isEmpty ? item.accentColor : tile.dominantColor
        )
    }

    if available.isEmpty, let raw = item.coverURL, !raw.isEmpty {
        let url = URL(string: raw)
        available.append(CollectionCoverSlot(
            thumbURL: url,
            previewURL: url,
            dominantColor: item.accentColor
        ))
    }

    guard let first = available.first else {
        let empty = CollectionCoverSlot(thumbURL: nil, previewURL: nil, dominantColor: item.accentColor)
        return [empty, empty, empty]
    }

    var slots = Array(available.prefix(3))
    while slots.count < 3 { slots.append(first) }
    return slots
}

struct CollectionListCard: View {
    let item: CollectionItem
    @State private var hovering = false

    private var slots: [CollectionCoverSlot] { collectionCoverSlots(item) }
    private var tintHex: String? { slots.first?.dominantColor ?? item.accentColor }
    private var tint: Color { tintHex.map { Color(hex: $0) } ?? Color.accent }
    private var title: String { item.title.isEmpty ? L10n.collections.untitledSet : item.title }
    private var source: String {
        item.kind == 1 ? L10n.collections.weeklyRecommendation : L10n.collections.kickerCollection
    }
    private var description: String {
        item.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            CollectionSteppedCover(slots: slots, fallbackColor: tintHex, cardHovering: hovering)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if item.isPublic == false { lockChip.padding(10) }
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(source.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 27, weight: .regular, design: .serif))
                        .tracking(-0.5)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(description.isEmpty ? " " : description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ink2)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .opacity(description.isEmpty ? 0 : 1)
                        .frame(height: 36, alignment: .topLeading)
                }
                .padding(.top, 10)

                Spacer(minLength: 0)

                HStack(alignment: .center) {
                    Text(L10n.collections.wallpaperCountLower(item.wallpaperCount).uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(Color.muted)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(hovering ? Color.ink : Color.muted)
                        .offset(x: hovering ? 3 : 0)
                }
            }
            .padding(.top, 16)
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 12)
            .frame(height: 152, alignment: .topLeading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.paper.blended(with: Color.paper2, fraction: hovering ? 0 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hovering ? Color.hair.blended(with: Color.ink, fraction: 0.38) : Color.hair, lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.09 : 0), radius: 16, y: 8)
        .offset(y: hovering ? -2 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.22), value: hovering)
        .onHover { hover in
            hovering = hover
            if hover { PaletteEnv.shared.apply(palette: nil, dominant: tintHex) }
            else { PaletteEnv.shared.resetToDefaults() }
        }
    }

    private var lockChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
            Text(L10n.collections.privateLabel.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.4)
        }
        .foregroundStyle(Color.chipInk)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.chipSurface))
    }
}

private struct CollectionSteppedCover: View {
    let slots: [CollectionCoverSlot]
    let fallbackColor: String?
    let cardHovering: Bool
    @State private var hoveredIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let weights = coverWeights
            let gap: CGFloat = 2
            let usableWidth = max(0, proxy.size.width - gap * CGFloat(max(0, slots.count - 1)))
            let weightTotal = max(1, weights.reduce(0, +))

            HStack(spacing: gap) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    CollectionCoverImage(slot: slot, fallbackColor: fallbackColor)
                        .frame(width: usableWidth * weights[index] / weightTotal, height: proxy.size.height)
                        .clipped()
                        .opacity(hoveredIndex == nil || hoveredIndex == index ? 1 : 0.82)
                        .saturation(hoveredIndex == nil || hoveredIndex == index ? 1 : 0.82)
                        .brightness(hoveredIndex == nil || hoveredIndex == index ? 0 : -0.04)
                        .onHover { hover in
                            if hover { hoveredIndex = index }
                            else if hoveredIndex == index { hoveredIndex = nil }
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(Color.paper2)
        .scaleEffect(cardHovering ? 1.018 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.hair, lineWidth: 1))
        .animation(.easeOut(duration: 0.38), value: hoveredIndex)
        .animation(.easeOut(duration: 0.38), value: cardHovering)
    }

    private var coverWeights: [CGFloat] {
        guard let hoveredIndex else { return [1.65, 1, 0.68] }
        return slots.indices.map { $0 == hoveredIndex ? 2.15 : 0.58 }
    }
}

private struct CollectionCoverImage: View {
    let slot: CollectionCoverSlot
    let fallbackColor: String?

    var body: some View {
        ProgressiveCachedAsyncImage(
            lowURL: slot.thumbURL ?? slot.previewURL,
            highURL: slot.previewURL ?? slot.thumbURL,
            lowMaxPixelDimension: 520,
            highMaxPixelDimension: 1200
        ) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color(hex: slot.dominantColor ?? fallbackColor ?? "#bbb").opacity(0.5)
        }
    }
}

struct CollectionListCardSkeleton: View {
    private let weights: [CGFloat] = [1.65, 1, 0.68]

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let usableWidth = max(0, proxy.size.width - gap * 2)
                let total = weights.reduce(0, +)
                HStack(spacing: gap) {
                    ForEach(weights.indices, id: \.self) { index in
                        collectionSkeletonSlot
                            .frame(width: usableWidth * weights[index] / total, height: proxy.size.height)
                    }
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.hair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 0) {
                SkeletonLine(width: 112, height: 8, cornerRadius: 2)
                SkeletonLine(width: 220, height: 28, cornerRadius: 3).padding(.top, 12)
                SkeletonLine(height: 8, cornerRadius: 2).padding(.top, 16)
                SkeletonLine(width: 180, height: 8, cornerRadius: 2).padding(.top, 8)
                Spacer(minLength: 0)
                SkeletonLine(width: 88, height: 8, cornerRadius: 2)
            }
            .padding(.top, 16)
            .padding(.leading, 10)
            .padding(.trailing, 42)
            .padding(.bottom, 12)
            .frame(height: 152, alignment: .topLeading)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.paper.blended(with: Color.paper2, fraction: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hair, lineWidth: 1))
    }

    private var collectionSkeletonSlot: some View {
        Color.paper2
            .overlay { ShimmerBand() }
            .overlay { ImageLoadingBeam(style: .skeleton) }
            .clipped()
    }
}

struct CollectionTileCard: View {
    let item: CollectionItem
    @State private var hover = false

    private var coverURL: URL? {
        if let p = item.recentTiles?.first?.previewURL, !p.isEmpty { return URL(string: p) }
        if let c = item.coverURL, !c.isEmpty { return URL(string: c) }
        if let t = item.recentTiles?.first?.thumbURL, !t.isEmpty { return URL(string: t) }
        return nil
    }
    private var kickerText: String {
        var s = item.kind == 1 ? L10n.collections.kickerEditorTheme : L10n.collections.kickerCollection
        if item.isPublic == false { s += " · " + L10n.collections.privateLabel }
        return s
    }
    // Tint for the stacked-paper layers (web mixes accent into hair).
    private var tintHex: String? { item.recentTiles?.first?.dominantColor ?? item.accentColor }
    private var tint: Color { tintHex.map { Color(hex: $0) } ?? Color.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 5) {
                Text(kickerText.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.0).foregroundStyle(Color.muted)
                Text(item.title.isEmpty ? L10n.collections.untitledSet : item.title)
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(L10n.collections.wallpaperCountCaps(item.wallpaperCount))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4).foregroundStyle(Color.muted)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.34), value: hover)
        .onHover { h in
            hover = h
            if h { PaletteEnv.shared.apply(palette: nil, dominant: tintHex) }
            else { PaletteEnv.shared.resetToDefaults() }
        }
    }

    // 1:1 cover with the web's stacked-paper effect: two offset,
    // accent-tinted layers behind the cover. 12pt is reserved at the
    // bottom-right so the deepest layer sits inside the cell.
    private var cover: some View {
        GeometryReader { geom in
            let cell = geom.size.width
            let card = max(0, cell - 12)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.hair.blended(with: tint, fraction: 0.18))
                    .frame(width: card, height: card)
                    .offset(x: hover ? 12 : 8, y: hover ? 12 : 8)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.hair.blended(with: tint, fraction: 0.30))
                    .frame(width: card, height: card)
                    .offset(x: hover ? 6 : 4, y: hover ? 6 : 4)
                Color.clear
                    .frame(width: card, height: card)
                    .overlay {
                        if let url = coverURL {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().aspectRatio(contentMode: .fill).scaleEffect(hover ? 1.04 : 1.0)
                            } placeholder: { Color.paper2 }
                        } else {
                            Color.paper2.overlay(
                                Text(L10n.collections.noCoverYet).font(.system(size: 10, design: .monospaced))
                                    .tracking(1.8).foregroundStyle(Color.muted))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hair, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if item.isPublic == false {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                                Text(L10n.collections.privateLabel.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.4)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                            .padding(8)
                        }
                    }
                    .offset(x: hover ? -2 : 0, y: hover ? -2 : 0)
                    .shadow(color: .black.opacity(hover ? 0.30 : 0.16), radius: hover ? 22 : 12, x: 0, y: hover ? 10 : 6)
            }
            .frame(width: cell, height: cell, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// Minimal create-collection sheet (title + public toggle).
struct NewCollectionSheet: View {
    var onCreated: () -> Void
    var onClose: () -> Void
    @State private var title = ""
    @State private var isPublic = true
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.collections.newCollection).font(.display20).foregroundStyle(Color.ink)
            TextField(L10n.collections.titlePlaceholder, text: $title).textFieldStyle(.roundedBorder)
            Toggle(L10n.collections.publicToggle, isOn: $isPublic).toggleStyle(.switch)
            if let e = error { Text(e).font(.sans11).foregroundStyle(Color.warn) }
            HStack {
                Spacer()
                Button(L10n.common.cancel) { onClose() }
                Button(creating ? L10n.collections.creating : L10n.collections.create) { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || creating)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func create() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        creating = true; error = nil
        Task {
            do {
                _ = try await APIClient.shared.createCollection(title: t, isPublic: isPublic)
                creating = false; onCreated(); onClose()
            } catch {
                creating = false; self.error = L10n.collections.createFailed
            }
        }
    }
}

// Collection detail — hero header + grid of wallpapers.
struct CollectionDetailView: View {
    let slug: String
    var onWallpaper: (Wallpaper) -> Void

    @State private var auth = AuthService.shared
    @State private var info: CollectionItem?
    @State private var curator: PublicProfile?
    @State private var items: [Wallpaper] = []
    @State private var loading = false
    @State private var loadError: String?

    // Inline edit (owner-only, hand-made collections only).
    @State private var editing = false
    @State private var editTitle = ""
    @State private var editDesc = ""
    @State private var editIsPublic = true
    @State private var saving = false

    // Only the owner may edit, and only their own kind=0 collections —
    // editor/weekly themes (kind=1) are admin-managed.
    private func canEdit(_ c: CollectionItem) -> Bool {
        guard let me = auth.user else { return false }
        return me.id == (c.userID ?? -1) && (c.kind ?? 0) == 0
    }

    private var setCountLabel: String {
        let total = info?.wallpaperCount ?? items.count
        if !items.isEmpty && items.count < total { return L10n.collections.countOfTotalCaps(items.count, total) }
        return L10n.collections.piecesCaps(total)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 24, alignment: .top)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if loading && info == nil && items.isEmpty {
                    detailSkeleton.padding(.top, 14)
                } else if let err = loadError, info == nil && items.isEmpty {
                    RemoteLoadErrorView(message: err) {
                        Task { await load() }
                    }
                    .padding(.top, 20)
                } else {
                    if let c = info { heroRow(c).padding(.top, 14) }

                    // "THE SET" head — mirrors the web's c-detail-grid-head.
                    HStack {
                        Text(L10n.collections.theSet)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(2.2).foregroundStyle(Color.muted)
                        Spacer()
                        Text(setCountLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.8).foregroundStyle(Color.muted)
                    }
                    .padding(.top, 34)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.hair.opacity(0.6)).frame(height: 1).offset(y: 12)
                    }

                    if loading && items.isEmpty {
                        WallpaperGridSkeleton(columns: gridColumns, count: 12, spacing: 24, aspectRatio: 3.0 / 4.0, cornerRadius: 6)
                            .padding(.top, 28)
                    } else if let err = loadError, items.isEmpty {
                        RemoteLoadErrorView(message: err) {
                            Task { await load() }
                        }
                    } else if items.isEmpty {
                        RemoteEmptyStateView(
                            title: L10n.collections.emptyDetailTitle,
                            message: L10n.collections.emptyDetailMessage,
                            symbol: "photo.stack"
                        )
                    } else {
                        // Framed-print grid — 3:4 paper-mat tiles like a gallery
                        // wall (the web's FramedTile / .cd-frame).
                        LazyVGrid(columns: gridColumns, spacing: 24) {
                            ForEach(items) { wp in
                                FramedTile(
                                    wallpaper: wp,
                                    accent: tint,
                                    onTap: { onWallpaper(wp) },
                                    onHover: { h in
                                        if h { PaletteEnv.shared.apply(palette: wp.colorPalette, dominant: wp.dominantColor) }
                                        else { applyBasePalette() }
                                    }
                                )
                            }
                        }
                        .padding(.top, 28)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: slug) { await load() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var tint: Color {
        (info?.recentTiles?.first?.dominantColor ?? info?.accentColor).map { Color(hex: $0) } ?? Color.accent
    }

    private var detailSkeleton: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(alignment: .top, spacing: 32) {
                SkeletonPlate(aspectRatio: 1, cornerRadius: 10)
                    .frame(width: 340, height: 340)
                VStack(alignment: .leading, spacing: 14) {
                    SkeletonLine(width: 128, height: 9)
                    SkeletonLine(width: 320, height: 36)
                    SkeletonLine(width: 420, height: 12)
                    SkeletonLine(width: 360, height: 12)
                    SkeletonLine(width: 180, height: 34, cornerRadius: 17)
                }
                Spacer(minLength: 0)
            }
            LabelRule(text: L10n.collections.theSet + " · …")
            WallpaperGridSkeleton(columns: gridColumns, count: 12, spacing: 24, aspectRatio: 3.0 / 4.0, cornerRadius: 6)
        }
    }

    // Hero row — a framed (paper-mat) cover on the left, kicker / title
    // / count on the right (mirrors the web collection-detail header).
    private func heroRow(_ c: CollectionItem) -> some View {
        HStack(alignment: .top, spacing: 32) {
            // Photo-frame: paper mat (16pt) + accent-tinted edge + a
            // soft accent halo, with the image in an inner chamber.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.paper)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.paper2)
                    .overlay {
                        if let cover = c.coverURL, let url = URL(string: cover) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.paper2 }
                        } else {
                            Text(L10n.collections.noCoverYet).font(.system(size: 10, design: .monospaced))
                                .tracking(1.8).foregroundStyle(Color.muted)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(16)
            }
            .frame(width: 340, height: 340)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.hair.blended(with: tint, fraction: 0.30), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.30), radius: 28, x: 0, y: 16)
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 14) {
                Text(((c.kind == 1 ? L10n.collections.kickerEditorTheme : L10n.collections.kickerCollection) + (c.isPublic == false ? " · " + L10n.collections.privateLabel : "")).uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.0).foregroundStyle(Color.muted)

                if editing {
                    editForm(c)
                } else {
                    Text(c.title).font(.display32).foregroundStyle(Color.ink)

                    if let desc = c.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 14)).foregroundStyle(Color.ink2)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }

                    if canEdit(c) {
                        Button(action: { editTitle = c.title; editDesc = c.description ?? ""; editIsPublic = c.isPublic ?? true; editing = true }) {
                            HStack(spacing: 5) {
                                Image(systemName: "pencil").font(.system(size: 10, weight: .semibold))
                                Text(L10n.collections.edit).font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.ink).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.paper)).overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                        }
                        .buttonStyle(.plain).pointerCursor()
                    }
                }

                // Byline — curator avatar + "A set by @handle" + count/updated.
                bylineRow(c)

                // Like pill (heart + count), matching the web c-detail-like.
                HStack(spacing: 6) {
                    Image(systemName: (c.isLiked ?? false) ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle((c.isLiked ?? false) ? tint : Color.ink2)
                    Text("\(c.likeCount ?? 0)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.ink2)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.paper2))
                .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                .padding(.top, 2)

                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private func bylineRow(_ c: CollectionItem) -> some View {
        let handle = curator?.username ?? "user-\(c.userID ?? 0)"
        let initial = String((curator?.nickname ?? curator?.username ?? "U").prefix(1)).uppercased()
        let sub: String = {
            var s = L10n.collections.wallpaperCountLower(c.wallpaperCount)
            if let u = c.updatedAt, !relativeCollTime(u).isEmpty { s += " · " + L10n.collections.updatedAgo(relativeCollTime(u)) }
            return s
        }()
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.18))
                if let a = curator?.avatarURL, let url = URL(string: a), !a.isEmpty {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.clear }
                    .clipShape(Circle())
                } else {
                    Text(initial)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.collections.setBy(handle))
                    .font(.system(size: 13, design: .serif)).foregroundStyle(Color.ink)
                Text(sub)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.4).foregroundStyle(Color.muted)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func editForm(_ c: CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.collections.titlePlaceholder, text: $editTitle)
                .textFieldStyle(.plain).font(.display32).foregroundStyle(Color.ink)
            TextField(L10n.collections.descPlaceholder, text: $editDesc, axis: .vertical)
                .textFieldStyle(.roundedBorder).font(.system(size: 14)).lineLimit(3, reservesSpace: true)
                .frame(maxWidth: 420)
            Toggle(isOn: $editIsPublic) {
                Text(editIsPublic ? L10n.collections.togglePublicOn : L10n.collections.togglePublicOff)
                    .font(.system(size: 12)).foregroundStyle(Color.ink2)
            }
            .toggleStyle(.switch).tint(Color.accent).frame(maxWidth: 420, alignment: .leading)
            HStack(spacing: 8) {
                Button(action: { Task { await saveEdit(c) } }) {
                    Text(saving ? L10n.collections.saving : L10n.collections.save).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.paper).padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(Color.ink))
                }.buttonStyle(.plain).disabled(saving || editTitle.trimmingCharacters(in: .whitespaces).isEmpty).pointerCursor()
                Button(action: { editing = false }) {
                    Text(L10n.common.cancel).font(.system(size: 12)).foregroundStyle(Color.ink2)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                }.buttonStyle(.plain).pointerCursor()
            }
        }
    }

    private func saveEdit(_ c: CollectionItem) async {
        let title = editTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        saving = true; defer { saving = false }
        do {
            try await APIClient.shared.updateCollection(id: c.id, title: title, description: editDesc, isPublic: editIsPublic)
            editing = false
            await load()
        } catch {}
    }

    private func applyBasePalette() {
        if let hex = info?.recentTiles?.first?.dominantColor ?? info?.accentColor {
            PaletteEnv.shared.apply(palette: nil, dominant: hex)
        } else {
            PaletteEnv.shared.resetToDefaults()
        }
    }

    private func load() async {
        loadError = nil
        loading = true; defer { loading = false }
        do {
            let c = try await APIClient.shared.fetchCollection(slug: slug)
            info = c
            applyBasePalette()
            // Curator handle + avatar for the byline — the /users/{id}
            // route resolves a numeric id, so pass user_id as the param.
            // Optional: the byline degrades to "user-N" if this fails.
            if let uid = c.userID {
                if let p = try? await APIClient.shared.fetchPublicProfile(username: String(uid)) {
                    curator = p
                }
            }
            let data = try await APIClient.shared.fetchCollectionWallpapers(collectionID: c.id, limit: 36)
            items = data.items
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Framed-print tile — a 3:4 paper "mat" with a hairline border + soft
// drop shadow, the image in an inner chamber. Hover lifts the frame,
// tints the edge to the collection accent, and scales the image. This
// is the Mac port of the web's FramedTile / .cd-frame.
struct FramedTile: View {
    let wallpaper: Wallpaper
    var accent: Color
    var onTap: () -> Void
    var onHover: (Bool) -> Void
    @State private var hovering = false

    @State private var manager = WallpaperManager.shared
    @State private var auth = AuthService.shared
    @State private var liked: Bool? = nil
    @State private var favorited: Bool? = nil
    @State private var downloaded: Bool? = nil
    @State private var busy = false
    @State private var transferAction: FramedTransferAction? = nil

    private var isLiked: Bool { liked ?? (wallpaper.isLiked ?? false) }
    private var isFavorited: Bool { favorited ?? (wallpaper.isFavorited ?? false) }
    private var localFileExists: Bool { manager.isDownloaded(wallpaper.id) }
    private var isOwnWallpaper: Bool { auth.user?.id == wallpaper.userID }
    private var isDownloaded: Bool { downloaded ?? (wallpaper.isDownloaded ?? localFileExists) }
    private var downloadHelp: String {
        if isDownloaded { return L10n.collections.downloadGotIt }
        if isOwnWallpaper { return L10n.collections.download }
        return L10n.collections.tradeForOne
    }
    private var isTransferring: Bool { manager.downloading.contains(wallpaper.id) }
    private var downloadProgress: Double? { manager.downloadProgress[wallpaper.id] }
    private var downloadButtonLoading: Bool { isTransferring && (transferAction == .download || transferAction == nil) }

    private var imageURL: URL? {
        let s = wallpaper.previewURL.isEmpty ? wallpaper.thumbURL : wallpaper.previewURL
        return URL(string: s)
    }
    private var resLabel: String? {
        let px = max(wallpaper.width, wallpaper.height)
        if px >= 7680 { return "8K" }
        if px >= 3840 { return "4K" }
        if px >= 2560 { return "2K" }
        if px >= 1920 { return "1080P" }
        if px >= 1280 { return "720P" }
        return nil
    }
    private var isVideo: Bool { wallpaper.fileType.hasPrefix("video/") }

    var body: some View {
        Button(action: onTap) {
            // Mat chamber — Color.clear establishes the 3:4 box, the fill
            // image rides in the overlay, and the clipShape on the whole
            // thing bounds the overflow (so big images don't leak past
            // the frame). Chips overlay on top, inside the mat.
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: imageURL) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        (wallpaper.dominantColor.map { Color(hex: $0) } ?? Color.paper2).opacity(0.5)
                    }
                    .scaleEffect(hovering ? 1.04 : 1.0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topLeading) { chips.padding(8) }
                .overlay(alignment: .bottomTrailing) { actionRail.padding(8) }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.paper2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(hovering ? Color.hair.blended(with: accent, fraction: 0.4) : Color.hair, lineWidth: 1)
                )
                .shadow(color: hovering ? accent.opacity(0.32) : Color.black.opacity(0.18),
                        radius: hovering ? 22 : 8, x: 0, y: hovering ? 14 : 6)
                .offset(y: hovering ? -3 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.32), value: hovering)
        .onHover { h in
            hovering = h
            onHover(h)
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder private var chips: some View {
        HStack(spacing: 5) {
            if let r = resLabel { tileChip(r, icon: nil) }
            if isVideo || wallpaper.isDynamic { tileChip(L10n.collections.liveChip, icon: "play.fill") }
            if wallpaper.isAIGenerated == true { tileChip("AI", icon: "sparkles") }
            Spacer(minLength: 0)
        }
    }

    private func tileChip(_ text: String, icon: String?) -> some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 8, weight: .bold)) }
            Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.4)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    // Hover-revealed action rail — Favorite · Like · Download.
    // Setting a wallpaper now lives in DetailPage, where display and
    // lock-screen targets can be chosen explicitly.
    @ViewBuilder private var actionRail: some View {
        VStack(spacing: 5) {
            ActionDot(icon: isFavorited ? "star.fill" : "star",
                      kind: .favorite, active: isFavorited,
                      help: isFavorited ? L10n.collections.unfavorite : L10n.collections.favorite,
                      busy: busy, size: 26, action: { Task { await toggleFavorite() } })
            ActionDot(icon: isLiked ? "heart.fill" : "heart",
                      kind: .like, active: isLiked,
                      help: isLiked ? L10n.collections.unlike : L10n.collections.like,
                      busy: busy, size: 26, action: { Task { await toggleLike() } })
            ActionDot(icon: isDownloaded ? "checkmark.circle.fill" : "tray.and.arrow.down",
                      kind: .download, active: isDownloaded,
                      help: downloadHelp,
                      busy: busy,
                      loading: downloadButtonLoading,
                      progress: downloadProgress,
                      size: 26,
                      action: { Task { await doDownload() } })
        }
        .opacity(hovering ? 1 : 0)
        .offset(y: hovering ? 0 : 4)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .allowsHitTesting(hovering)
    }

    private func toggleLike() async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isLiked; liked = !prev
        do {
            if prev { try await APIClient.shared.unlike(wallpaperID: wallpaper.id) }
            else    { try await APIClient.shared.like(wallpaperID: wallpaper.id) }
        } catch { liked = prev }
    }
    private func toggleFavorite() async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isFavorited; favorited = !prev
        do {
            if prev { try await APIClient.shared.unfavorite(wallpaperID: wallpaper.id) }
            else    { try await APIClient.shared.favorite(wallpaperID: wallpaper.id) }
        } catch { favorited = prev }
    }
    private func doDownload() async {
        guard auth.isLoggedIn else { auth.login(); return }
        if localFileExists { return }
        busy = true; transferAction = .download
        defer { busy = false; transferAction = nil }
        do { try await manager.download(wallpaper: wallpaper); downloaded = true; await auth.refreshProfile() } catch {}
    }
}

private enum FramedTransferAction {
    case download
}

// Relative-time formatter for the collection byline — mirrors the web's
// relativeTime(): just now / N min / N hr / N days / N months / N years.
fileprivate func relativeCollTime(_ iso: String) -> String {
    let withFrac = ISO8601DateFormatter()
    withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = withFrac.date(from: iso) ?? plain.date(from: iso) else { return "" }
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return L10n.collections.timeJustNow }
    if diff < 3600 { return L10n.collections.timeMinAgo(Int(diff / 60)) }
    if diff < 86400 { return L10n.collections.timeHrAgo(Int(diff / 3600)) }
    let days = Int(diff / 86400)
    if days < 30 { return L10n.collections.timeDaysAgo(days) }
    let months = days / 30
    if months < 12 { return L10n.collections.timeMonthsAgo(months) }
    let years = months / 12
    return L10n.collections.timeYearsAgo(years)
}
