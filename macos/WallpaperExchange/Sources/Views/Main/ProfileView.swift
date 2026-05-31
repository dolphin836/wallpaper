import SwiftUI

// Public user profile. Editorial header (avatar + serif name + bio +
// stats), tab segment for Uploaded / Liked / Favorited / Downloads
// (the latter is owner-only; falls back to Uploaded when viewing
// someone else's profile), then a grid below.
struct ProfileView: View {
    let username: String
    var onWallpaper: (Wallpaper) -> Void

    @State private var profile: PublicProfile?
    @State private var items: [Wallpaper] = []
    @State private var tab: Tab = .uploaded
    @State private var loading = false
    @State private var loadError: String?
    @State private var auth = AuthService.shared

    enum Tab: String, CaseIterable {
        case uploaded = "Uploaded", liked = "Liked", favorited = "Favorited", downloads = "Downloads"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let p = profile {
                VStack(alignment: .leading, spacing: 28) {
                    header(profile: p)
                    tabRow
                    grid
                }
                .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity, alignment: .center)
            } else if let err = loadError {
                Text(err).font(.sans12).foregroundStyle(Color.muted).padding(.top, 60)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .task(id: username) { await loadProfile() }
        .task(id: "tab-\(tab.rawValue)") { await loadItems() }
    }

    private func header(profile p: PublicProfile) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Circle().fill(Color.paper2).frame(width: 96, height: 96)
                .overlay {
                    if let avatar = p.avatarURL, !avatar.isEmpty, let url = URL(string: avatar) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Text(String((p.nickname?.isEmpty == false ? p.nickname! : p.username).prefix(1)).uppercased())
                                .font(.display32).foregroundStyle(Color.ink)
                        }
                    } else {
                        Text(String((p.nickname?.isEmpty == false ? p.nickname! : p.username).prefix(1)).uppercased())
                            .font(.display32).foregroundStyle(Color.ink)
                    }
                }
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "Uploader · Member since \(monthYear(p.createdAt))")
                Text(p.nickname?.isEmpty == false ? p.nickname! : "@\(p.username)")
                    .font(.display32).foregroundStyle(Color.ink)
                if let bio = p.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.sans13).foregroundStyle(Color.muted)
                        .frame(maxWidth: 600, alignment: .leading)
                }
                HStack(spacing: 24) {
                    statBlock("UPLOADS", "\(p.uploadCount ?? 0)")
                    statBlock("DOWNLOADS", "\(p.downloadCount ?? 0)")
                    statBlock("LIKES", "\(p.likeCount ?? 0)")
                    statBlock("COLLECTIONS", "\(p.collectionCount ?? 0)")
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: label)
            Text(value).font(.displayLg).foregroundStyle(Color.ink)
        }
    }

    private var visibleTabs: [Tab] {
        // Downloads/favorites/likes are private-by-default on the
        // server unless the user has flipped the visibility toggle.
        // For self-view, always show all 4. For others, just Uploaded.
        if let u = auth.user, u.username == username { return Tab.allCases }
        return [.uploaded]
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs, id: \.self) { t in
                Button(action: { tab = t }) {
                    Text(t.rawValue)
                        .font(.sans12)
                        .foregroundStyle(tab == t ? Color.ink : Color.muted)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(tab == t ? Color.paper : Color.clear))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(4)
        .background(Capsule().fill(Color.paper2))
        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var grid: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView()
            } else if items.isEmpty {
                Text("Nothing here yet.")
                    .font(.sans13).foregroundStyle(Color.muted).padding(.top, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(items) { wp in
                        Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadProfile() async {
        loadError = nil
        do {
            profile = try await APIClient.shared.fetchPublicProfile(username: username)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadItems() async {
        items = []
        loading = true; defer { loading = false }
        do {
            let data: PaginatedData<Wallpaper>
            switch tab {
            case .uploaded:  data = try await APIClient.shared.fetchUserUploads(username: username, limit: 36)
            case .liked:     data = try await APIClient.shared.fetchUserLikes(username: username, limit: 36)
            case .favorited: data = try await APIClient.shared.fetchUserFavorites(username: username, limit: 36)
            case .downloads: data = try await APIClient.shared.fetchUserDownloads(username: username, limit: 36)
            }
            items = data.items
        } catch {}
    }

    private func monthYear(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }
}
