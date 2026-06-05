import SwiftUI
import AppKit

// Public collections list. Loads /collections (cursor-paginated) and
// renders cards with a 2×2 cover composition built from recent_tiles.
struct CollectionsListView: View {
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if loading && items.isEmpty {
                    ProgressView().padding(.top, 50).frame(maxWidth: .infinity)
                } else if let err = loadError, items.isEmpty {
                    Text(err).font(.sans12).foregroundStyle(Color.warn).padding(.top, 30)
                } else if visible.isEmpty {
                    Text(filter == .yours ? "You haven't created any collections yet." : "No collections yet.")
                        .font(.sans13).foregroundStyle(Color.muted)
                        .padding(.top, 50).frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24, alignment: .top)], spacing: 28) {
                        ForEach(visible) { c in
                            NavigationLink(value: MainWindow.MainRoute.collection(slug: c.slug, title: c.title)) {
                                CollectionTileCard(item: c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 28)
                    pagination.padding(.top, 28)
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
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
                Kicker(text: "The Library")
                Text("Crates, curated.").font(.display32).foregroundStyle(Color.ink)
                Text("Themed sets put together by the community and the editors. Each collection has its own colour, voice, and pace.")
                    .font(.sans13).foregroundStyle(Color.ink2)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                filterChip("All", on: filter == .all) { filter = .all }
                if auth.isLoggedIn {
                    filterChip("Yours", on: filter == .yours) { filter = .yours }
                    Button { showCreate = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            Text("New").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Prev / page / Next pagination (cursor-backed), mirroring the web.
    @ViewBuilder
    private var pagination: some View {
        HStack(spacing: 12) {
            Spacer()
            pageButton("‹ Prev", enabled: page > 0 && !loading) {
                Task { await loadPage(page - 1) }
            }
            if loading {
                ProgressView().controlSize(.small).frame(width: 60)
            } else {
                Text("Page \(page + 1)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.5).foregroundStyle(Color.ink2).frame(minWidth: 60)
            }
            pageButton("Next ›", enabled: hasMore && !loading) {
                Task { await loadPage(page + 1) }
            }
            Spacer()
        }
    }

    private func pageButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? Color.ink2 : Color.muted.opacity(0.5))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Color.paper2))
                .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func filterChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Color.paper : Color.ink2)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(on ? Color.ink : Color.paper))
                .overlay(Capsule().stroke(on ? Color.ink : Color.hair, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

// Web .c-tile — a clean 1:1 cover with the caption (kicker / title /
// count) BELOW the image rather than overlaid on it.
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
        var s = item.kind == 1 ? "Editor Theme" : "Collection"
        if item.isPublic == false { s += " · Private" }
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
                Text(item.title.isEmpty ? "Untitled set" : item.title)
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text("\(item.wallpaperCount) \(item.wallpaperCount == 1 ? "WALLPAPER" : "WALLPAPERS")")
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
                                Text("NO COVER YET").font(.system(size: 10, design: .monospaced))
                                    .tracking(1.8).foregroundStyle(Color.muted))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hair, lineWidth: 1))
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
            Text("New collection").font(.display20).foregroundStyle(Color.ink)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Toggle("Public", isOn: $isPublic).toggleStyle(.switch)
            if let e = error { Text(e).font(.sans11).foregroundStyle(Color.warn) }
            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                Button(creating ? "Creating…" : "Create") { create() }
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
                creating = false; self.error = "Couldn't create. Try again."
            }
        }
    }
}

// Collection detail — hero header + grid of wallpapers.
struct CollectionDetailView: View {
    let slug: String
    var onWallpaper: (Wallpaper) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var info: CollectionItem?
    @State private var curator: PublicProfile?
    @State private var items: [Wallpaper] = []
    @State private var loading = false

    private var setCountLabel: String {
        let total = info?.wallpaperCount ?? items.count
        if !items.isEmpty && items.count < total { return "\(items.count) OF \(total)" }
        return "\(total) \(total == 1 ? "PIECE" : "PIECES")"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: "All collections") { dismiss() }

                if let c = info { heroRow(c).padding(.top, 14) }

                // "THE SET" head — mirrors the web's c-detail-grid-head.
                HStack {
                    Text("THE SET")
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
                    ProgressView().padding(.top, 40).frame(maxWidth: .infinity)
                } else {
                    // Framed-print grid — 3:4 paper-mat tiles like a gallery
                    // wall (the web's FramedTile / .cd-frame).
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 24, alignment: .top)], spacing: 24) {
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
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
        }
        .task(id: slug) { await load() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var tint: Color {
        (info?.recentTiles?.first?.dominantColor ?? info?.accentColor).map { Color(hex: $0) } ?? Color.accent
    }

    // Hero row — a framed (paper-mat) cover on the left, kicker / title
    // / count on the right (mirrors the web collection-detail header).
    private func heroRow(_ c: CollectionItem) -> some View {
        HStack(alignment: .top, spacing: 32) {
            // Photo-frame: paper mat (16pt) + accent-tinted edge + a
            // soft accent halo, with the image in an inner chamber.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.paper)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.paper2)
                    .overlay {
                        if let cover = c.coverURL, let url = URL(string: cover) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.paper2 }
                        } else {
                            Text("NO COVER YET").font(.system(size: 10, design: .monospaced))
                                .tracking(1.8).foregroundStyle(Color.muted)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                Text(((c.kind == 1 ? "Editor Theme" : "Collection") + (c.isPublic == false ? " · Private" : "")).uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.0).foregroundStyle(Color.muted)
                Text(c.title).font(.display32).foregroundStyle(Color.ink)

                if let desc = c.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 14)).foregroundStyle(Color.ink2)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
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
            var s = "\(c.wallpaperCount) \(c.wallpaperCount == 1 ? "wallpaper" : "wallpapers")"
            if let u = c.updatedAt, !relativeCollTime(u).isEmpty { s += " · updated \(relativeCollTime(u))" }
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
                Text("A set by @\(handle)")
                    .font(.system(size: 13, design: .serif)).foregroundStyle(Color.ink)
                Text(sub)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.4).foregroundStyle(Color.muted)
            }
        }
        .padding(.top, 4)
    }

    private func applyBasePalette() {
        if let hex = info?.recentTiles?.first?.dominantColor ?? info?.accentColor {
            PaletteEnv.shared.apply(palette: nil, dominant: hex)
        } else {
            PaletteEnv.shared.resetToDefaults()
        }
    }

    private func load() async {
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
        } catch {}
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
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(alignment: .topLeading) { chips.padding(8) }
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
            if isVideo || wallpaper.isDynamic { tileChip("Live", icon: "play.fill") }
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
}

// Relative-time formatter for the collection byline — mirrors the web's
// relativeTime(): just now / N min / N hr / N days / N months / N years.
fileprivate func relativeCollTime(_ iso: String) -> String {
    let withFrac = ISO8601DateFormatter()
    withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = withFrac.date(from: iso) ?? plain.date(from: iso) else { return "" }
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    if diff < 3600 { return "\(Int(diff / 60)) min ago" }
    if diff < 86400 { return "\(Int(diff / 3600)) hr ago" }
    let days = Int(diff / 86400)
    if days < 30 { return "\(days) \(days == 1 ? "day" : "days") ago" }
    let months = days / 30
    if months < 12 { return "\(months) \(months == 1 ? "month" : "months") ago" }
    let years = months / 12
    return "\(years) \(years == 1 ? "year" : "years") ago"
}
