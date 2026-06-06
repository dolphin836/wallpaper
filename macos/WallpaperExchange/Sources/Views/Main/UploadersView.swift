import SwiftUI

// Top uploaders index. Sortable by trending / newest / most-downloaded
// — defaults to trending. Each row: avatar + name + bio + 3-thumb
// strip + total downloads + wallpaper count. Clicking jumps to the
// profile page.
struct UploadersView: View {
    var onPick: (String) -> Void

    @State private var items: [UploaderListItem] = []
    @State private var sort: String = "trending"
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Top contributors · this week")
                    HStack(alignment: .firstTextBaseline) {
                        Text("Uploaders").font(.display32).foregroundStyle(Color.ink)
                        Spacer()
                        sortPicker
                    }
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }

                if loading && items.isEmpty {
                    CardListSkeleton(rows: 4)
                } else if let err = loadError {
                    RemoteLoadErrorView(message: err) {
                        Task { await load() }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(items) { u in
                            Button(action: { onPick(u.username) }) {
                                UploaderCard(item: u)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .task(id: sort) { await load() }
    }

    private var sortPicker: some View {
        HStack(spacing: 4) {
            ForEach(["trending", "newest", "downloads"], id: \.self) { s in
                let label = s.capitalized
                Button(action: { sort = s }) {
                    Text(label)
                        .font(.sans11)
                        .foregroundStyle(sort == s ? Color.ink : Color.muted)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(sort == s ? Color.paper : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.paper2))
        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
    }

    private func load() async {
        loadError = nil
        loading = true; defer { loading = false }
        do {
            let resp = try await APIClient.shared.fetchUploaders(sort: sort, page: 1, limit: 36)
            items = resp.items
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct UploaderCard: View {
    let item: UploaderListItem
    @State private var hover = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 56px avatar.
            Circle().fill(Color.paper2)
                .frame(width: 56, height: 56)
                .overlay {
                    if !item.avatarURL.isEmpty, let url = URL(string: item.avatarURL) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Text(String((item.nickname.isEmpty ? item.username : item.nickname).prefix(1)).uppercased())
                                .font(.displayLg).foregroundStyle(Color.ink)
                        }
                    } else {
                        Text(String((item.nickname.isEmpty ? item.username : item.nickname).prefix(1)).uppercased())
                            .font(.displayLg).foregroundStyle(Color.ink)
                    }
                }
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.nickname.isEmpty ? "@\(item.username)" : item.nickname)
                    .font(.displayMd).foregroundStyle(Color.ink).lineLimit(1)
                Text("@\(item.username)")
                    .font(.mono10).tracking(0.5).foregroundStyle(Color.muted)
                if !item.bio.isEmpty {
                    Text(item.bio)
                        .font(.sans11).foregroundStyle(Color.muted)
                        .lineLimit(2)
                }
                HStack(spacing: 14) {
                    metric(label: "UPLOADS", value: "\(item.wallpaperCount)")
                    metric(label: "DOWNLOADS", value: "\(item.totalDownloads)")
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)

            // 3-thumb strip on the right.
            if let thumbs = item.recentThumbs, !thumbs.isEmpty {
                VStack(spacing: 3) {
                    ForEach(Array(thumbs.prefix(3).enumerated()), id: \.offset) { i, url in
                        CachedAsyncImage(url: URL(string: url)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(hex: item.recentTints?[safe: i] ?? "#bbb").opacity(0.5)
                        }
                        .frame(width: 38, height: 26)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover ? Color.paper : Color.paper.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
        .scaleEffect(hover ? 1.005 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.mono11).foregroundStyle(Color.ink)
            Text(label).font(.kicker).tracking(1.6).foregroundStyle(Color.muted)
        }
    }
}

// Small safe-index helper used to align recentTints to recentThumbs
// without crashing on a length mismatch.
extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
