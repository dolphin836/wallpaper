import SwiftUI

// Public collections list. Loads /collections (cursor-paginated) and
// renders cards with a 2×2 cover composition built from recent_tiles.
struct CollectionsListView: View {
    @State private var auth = AuthService.shared
    @State private var items: [CollectionItem] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var filter: Filter = .all
    @State private var showCreate = false

    enum Filter { case all, yours }

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
                            .onAppear { maybeLoadMore(c) }
                        }
                    }
                    .padding(.top, 28)
                    if hasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
                            .frame(height: 24).padding(.top, 16)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await reload() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.paper2
                if let url = coverURL {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.paper2 }
                } else {
                    Text("No cover yet").font(.mono10).foregroundStyle(Color.muted)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hair, lineWidth: 1))
            .scaleEffect(hover ? 1.01 : 1.0)
            .shadow(color: .black.opacity(hover ? 0.16 : 0.06), radius: hover ? 16 : 8, x: 0, y: hover ? 8 : 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(kickerText.uppercased())
                    .font(.kicker).tracking(1.6).foregroundStyle(Color.muted)
                Text(item.title.isEmpty ? "Untitled set" : item.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ink).lineLimit(1)
                Text("\(item.wallpaperCount) \(item.wallpaperCount == 1 ? "wallpaper" : "wallpapers")")
                    .font(.mono10).tracking(0.4).foregroundStyle(Color.muted)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: hover)
        .onHover { hover = $0 }
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
