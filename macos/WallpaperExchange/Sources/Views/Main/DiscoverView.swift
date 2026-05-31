import SwiftUI

// Main 'Discover' content. Editorial header (kicker + serif headline +
// intro), filter pills, adaptive 16:9 grid. `deviceMatch=true` switches
// to the Mac's screen resolution filter (used by the For Your Device
// sidebar entry).
struct DiscoverView: View {
    let search: String
    var onPick: (Wallpaper) -> Void
    var deviceMatch: Bool = false

    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var filter: Filter = .latest

    enum Filter: String, CaseIterable {
        case latest = "Latest", forYou = "For You", trending = "Trending",
             myDevice = "My Device", dynamic = "Dynamic", ai = "AI"
    }

    private var filtered: [Wallpaper] {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(s) ||
            ($0.dominantColor?.lowercased().contains(s) ?? false)
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                editorialHeader
                filterRow

                if loading && items.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.top, 60)
                } else if let err = loadError {
                    errorBanner(err)
                } else if filtered.isEmpty {
                    Text("No wallpapers match.").font(.sans13).foregroundStyle(Color.muted)
                        .padding(.top, 20)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)],
                        spacing: 16
                    ) {
                        ForEach(filtered) { wp in
                            Button(action: { onPick(wp) }) {
                                MainGridTile(wallpaper: wp)
                            }
                            .buttonStyle(.plain)
                            .onAppear { maybeLoadMore(wp) }
                        }
                    }
                    if hasMore {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small).opacity(loading ? 1 : 0)
                            Spacer()
                        }
                        .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 60)
        }
        .task(id: "discover-\(deviceMatch)") { await reload() }
    }

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: deviceMatch ? "Matched to your screen · live filter" : "Today · curated")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(deviceMatch ? "Wallpapers sized for" : "Find something for your")
                    .font(.display32).foregroundStyle(Color.ink)
                Text("Mac.").font(.display32).foregroundStyle(Color.accent)
            }
            Text("Hand-picked wallpapers from the community. Hover any tile for one-click set, or open the detail page for full controls.")
                .font(.sans13)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let isOn = filter == f
                Button(action: { filter = f; Task { await reload() } }) {
                    Text(f.rawValue)
                        .font(.sans12)
                        .foregroundStyle(isOn ? Color.paper : Color.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(isOn ? Color.ink : Color.paper2))
                        .overlay(Capsule().stroke(Color.hair, lineWidth: isOn ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11)).foregroundStyle(Color.warn)
            Text(msg).font(.sans11).foregroundStyle(Color.ink2).lineLimit(2)
            Spacer()
            Button("Retry") { Task { await reload() } }.controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.warn.opacity(0.06)))
    }

    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false; loadError = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await APIClient.shared.fetchWallpapers(
                cursor: cursor,
                limit: 24,
                dynamicOnly: filter == .dynamic
            )
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Downloaded / Liked / Uploaded share the same justified-grid skeleton;
// each just feeds a different fetcher.
struct DownloadsView: View {
    var onPick: (Wallpaper) -> Void
    @State private var auth = AuthService.shared
    @State private var items: [Wallpaper] = []
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Kicker(text: "Files saved locally — \(items.count)")
                Text("Downloads").font(.display32).foregroundStyle(Color.ink)
                if loading && items.isEmpty {
                    ProgressView()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(items) { wp in
                            Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
        }
        .task { await reload() }
    }
    private func reload() async {
        guard auth.isLoggedIn else { return }
        loading = true; defer { loading = false }
        if let data = try? await APIClient.shared.fetchMyDownloads(limit: 36) {
            items = data.items
        }
    }
}

struct MyLikesView: View {
    var onPick: (Wallpaper) -> Void
    @State private var auth = AuthService.shared
    @State private var items: [Wallpaper] = []
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Kicker(text: "Wallpapers you've liked")
                Text("Liked").font(.display32).foregroundStyle(Color.ink)
                if loading && items.isEmpty { ProgressView() }
                else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(items) { wp in
                            Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }.padding(.horizontal, 32).padding(.vertical, 24)
        }
        .task { await reload() }
    }
    private func reload() async {
        guard auth.isLoggedIn, let u = auth.user else { return }
        loading = true; defer { loading = false }
        if let data = try? await APIClient.shared.fetchUserLikes(username: u.username, limit: 36) {
            items = data.items
        }
    }
}

struct MyUploadsView: View {
    var onPick: (Wallpaper) -> Void
    @State private var auth = AuthService.shared
    @State private var items: [Wallpaper] = []
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Kicker(text: "Wallpapers you've uploaded")
                Text("Uploaded by Me").font(.display32).foregroundStyle(Color.ink)
                if loading && items.isEmpty { ProgressView() }
                else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(items) { wp in
                            Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }.padding(.horizontal, 32).padding(.vertical, 24)
        }
        .task { await reload() }
    }
    private func reload() async {
        guard auth.isLoggedIn, let u = auth.user else { return }
        loading = true; defer { loading = false }
        if let data = try? await APIClient.shared.fetchUserUploads(username: u.username, limit: 36) {
            items = data.items
        }
    }
}
