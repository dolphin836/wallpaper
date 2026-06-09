import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Unified account / profile page — the Mac port of the web ProfilePage.
// One editorial header (with owner inline-editing + avatar + balance +
// Edit/Password/Upload pills) + an underline tab bar with count badges +
// per-tab paged content. For the signed-in owner the tab list gains a
// Mac-only "Settings" tab (first) plus owner-only Downloads / Coin
// ledger. All grids use prev/next pagination (no infinite scroll).
struct AccountView: View {
    let username: String
    var initialTab: AccountTab = .uploads
    var onWallpaper: (Wallpaper) -> Void
    var onCollection: (CollectionItem) -> Void
    var onUpload: () -> Void = {}

    @State private var auth = AuthService.shared
    @State private var profile: PublicProfile?
    @State private var loadError: String?
    @State private var tab: AccountTab = .uploads
    @State private var didInit = false
    @State private var counts: [AccountTab: Int] = [:]

    private var isOwner: Bool {
        guard let me = auth.user else { return false }
        return me.username == username
    }

    private var tabs: [AccountTab] {
        if isOwner {
            return [.settings, .downloads, .uploads, .collections, .favorites, .likes, .ledger]
        }
        return [.uploads, .collections, .favorites, .likes]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let p = profile {
                    AccountHeader(profile: p, isOwner: isOwner, onUpload: onUpload,
                                  onChanged: { await loadProfile() })
                    tabBar
                    content(p).padding(.top, 26)
                } else if let err = loadError {
                    RemoteLoadErrorView(message: err) {
                        Task {
                            await loadProfile()
                            await prefetchCounts()
                        }
                    }
                    .padding(.top, 36)
                } else {
                    accountSkeleton
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1180).frame(maxWidth: .infinity, alignment: .center)
        }
        .task(id: username) {
            if !didInit { tab = initialTab; didInit = true }
            await loadProfile()
            await prefetchCounts()
        }
        .onChange(of: initialTab) { _, new in tab = new }
        // Tabs with no imagery (Settings / Ledger) fall back to the warm
        // brand mesh; image tabs set their base palette via onPalette.
        .onChange(of: tab) { _, new in if new == .settings { PaletteEnv.shared.resetToDefaults() } }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var accountSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProfileHeaderSkeleton()
            HStack(spacing: 22) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonLine(width: 104, height: 38, cornerRadius: 4)
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
            WallpaperGridSkeleton(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top)],
                count: 12
            )
            .padding(.top, 2)
        }
    }

    // Drive the page-mesh background. A nil palette/dominant means the
    // tab has nothing to tint from → fall back to the brand mesh.
    private func applyMesh(_ palette: String?, _ dominant: String?) {
        if palette == nil && (dominant == nil || dominant?.isEmpty == true) {
            PaletteEnv.shared.resetToDefaults()
        } else {
            PaletteEnv.shared.apply(palette: palette, dominant: dominant)
        }
    }

    private func loadProfile() async {
        loadError = nil
        do { profile = try await APIClient.shared.fetchPublicProfile(username: username) }
        catch { loadError = error.localizedDescription }
    }

    // Counts shown on the tabs — fetched cheaply (limit 1, reading the
    // `total`) so the badges are populated before each tab is visited.
    // Each tab's grid also reports its real total back as it loads.
    private func prefetchCounts() async {
        for t in tabs where t != .settings {
            if let c = try? await countFor(t) { counts[t] = c }
        }
    }
    private func countFor(_ t: AccountTab) async throws -> Int {
        switch t {
        case .uploads:     return try await APIClient.shared.fetchUserUploads(username: username, limit: 1, status: "1").total ?? 0
        case .collections: return try await APIClient.shared.fetchUserCollections(idOrUsername: username, limit: 1).total ?? 0
        case .favorites:   return try await APIClient.shared.fetchUserFavorites(username: username, limit: 1).total ?? 0
        case .likes:       return try await APIClient.shared.fetchUserLikes(username: username, limit: 1).total ?? 0
        case .downloads:   return try await APIClient.shared.fetchUserDownloads(username: username, limit: 1).total ?? 0
        case .ledger:      return try await APIClient.shared.fetchCoinTransactions(limit: 1).total ?? 0
        case .settings:    return 0
        }
    }

    // ─── Tab bar (web .ptabs + .ptab-count) ──────────────────────
    // Single row that scrolls horizontally when it can't fit (never
    // wraps), with a full-width base hairline underneath.
    private var tabBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(tabs, id: \.self) { t in tabButton(t) }
                }
                .padding(.top, 18)
            }
            Rectangle().fill(Color.hair).frame(height: 1)
        }
    }

    private func tabButton(_ t: AccountTab) -> some View {
        Button(action: { tab = t }) {
            HStack(spacing: 8) {
                Image(systemName: t.icon).font(.system(size: 12, weight: .medium))
                Text(t.label).font(.system(size: 14, weight: .medium)).lineLimit(1).fixedSize()
                if let c = counts[t] {
                    Text("\(c)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.4)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .foregroundStyle(tab == t ? Color.paper : Color.muted)
                        .background(RoundedRectangle(cornerRadius: 3).fill(tab == t ? Color.ink : Color.paper2))
                }
            }
            .foregroundStyle(tab == t ? Color.ink : Color.muted)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(tab == t ? Color.ink : Color.clear).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor()
    }

    // ─── Tab content ─────────────────────────────────────────────
    @ViewBuilder private func content(_ p: PublicProfile) -> some View {
        switch tab {
        case .settings:
            AccountSettingsTab()
        case .uploads:
            AccountUploadsTab(username: username, isOwner: isOwner,
                              onWallpaper: onWallpaper, onCount: { counts[.uploads] = $0 },
                              onPalette: applyMesh)
        case .collections:
            PagedCollectionGrid(
                headLabel: "CREATED",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserCollections(idOrUsername: username, cursor: cursor, limit: limit) },
                onCollection: onCollection, onCount: { counts[.collections] = $0 }, onPalette: applyMesh
            ).id("collections-\(username)")
        case .favorites:
            wallpaperList(.favorites, head: "FAVORITES", empty: "No favorites yet.",
                          isPublic: auth.user?.favoritesPublic ?? false, noun: "favorites",
                          fetch: { c, l in try await APIClient.shared.fetchUserFavorites(username: username, cursor: c, limit: l) },
                          toggle: { v in Task { try? await APIClient.shared.updatePrivacy(favoritesPublic: v); await auth.refreshProfile() } })
        case .likes:
            wallpaperList(.likes, head: "LIKES", empty: "No likes yet.",
                          isPublic: auth.user?.likesPublic ?? false, noun: "likes",
                          fetch: { c, l in try await APIClient.shared.fetchUserLikes(username: username, cursor: c, limit: l) },
                          toggle: { v in Task { try? await APIClient.shared.updatePrivacy(likesPublic: v); await auth.refreshProfile() } })
        case .downloads:
            VStack(alignment: .leading, spacing: 22) {
                if isOwner {
                    downloadsAutoShufflePanel
                }
                wallpaperList(.downloads, head: "DOWNLOADS", empty: "No downloads yet.",
                              isPublic: auth.user?.downloadsPublic ?? false, noun: "downloads",
                              fetch: { c, l in try await APIClient.shared.fetchUserDownloads(username: username, cursor: c, limit: l) },
                              toggle: { v in Task { try? await APIClient.shared.updatePrivacy(downloadsPublic: v); await auth.refreshProfile() } },
                              flagIfNotLocal: true)
            }
        case .ledger:
            LedgerTab(onCount: { counts[.ledger] = $0 }, onPalette: applyMesh)
        }
    }

    private var downloadsAutoShufflePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AUTO-SHUFFLE")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.muted)
                .padding(.bottom, 8)

            AutoShuffleSettings()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.paper.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.hair, lineWidth: 1)
                )
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    @ViewBuilder
    private func wallpaperList(_ t: AccountTab, head: String, empty: String,
                               isPublic: Bool, noun: String,
                               fetch: @escaping (_ c: Int?, _ l: Int) async throws -> PaginatedData<Wallpaper>,
                               toggle: @escaping (Bool) -> Void,
                               flagIfNotLocal: Bool = false) -> some View {
        PagedWallpaperGrid(
            headLabel: head, emptyText: empty,
            privacyNoun: isOwner ? noun : nil, privacyIsPublic: isPublic,
            onTogglePrivacy: toggle,
            fetch: fetch, onWallpaper: onWallpaper, onCount: { counts[t] = $0 }, onPalette: applyMesh,
            flagIfNotLocal: flagIfNotLocal
        ).id("\(noun)-\(username)")
    }
}

enum AccountTab: String, Hashable {
    case settings, uploads, collections, favorites, likes, downloads, ledger
    var label: String {
        switch self {
        case .settings: "Settings"
        case .uploads: "Uploads"
        case .collections: "Collections"
        case .favorites: "Favorites"
        case .likes: "Likes"
        case .downloads: "Downloads"
        case .ledger: "Coin ledger"
        }
    }
    var icon: String {
        switch self {
        case .settings: "gearshape"
        case .uploads: "photo"
        case .collections: "square.grid.2x2"
        case .favorites: "star"
        case .likes: "heart"
        case .downloads: "arrow.down.circle"
        case .ledger: "bolt"
        }
    }
}

// ─── Editorial header (avatar + identity + balance + pills) ──────
struct AccountHeader: View {
    let profile: PublicProfile
    let isOwner: Bool
    var onUpload: () -> Void
    var onChanged: () async -> Void

    @State private var auth = AuthService.shared
    @State private var editing = false
    @State private var editNickname = ""
    @State private var editBio = ""
    @State private var saving = false
    @State private var showPassword = false
    @State private var oldPw = ""
    @State private var newPw = ""
    @State private var savingPw = false
    @State private var pwError: String?

    // For the owner, render live from auth.user so edits/avatar reflect
    // immediately; otherwise from the fetched public profile.
    private var displayName: String {
        if isOwner, let u = auth.user { return u.nickname.isEmpty ? u.username : u.nickname }
        return profile.nickname?.isEmpty == false ? profile.nickname! : profile.username
    }
    private var bioText: String {
        if isOwner, let u = auth.user { return u.bio }
        return profile.bio ?? ""
    }
    private var avatarURLString: String? {
        if isOwner { return auth.user?.avatarURL }
        return profile.avatarURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            avatar.frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 8) {
                Text("Contributor · Member since \(memberSince(profile.createdAt))".uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(Color.muted)

                if editing {
                    TextField("Nickname", text: $editNickname)
                        .textFieldStyle(.plain).font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ink)
                    TextField("Bio", text: $editBio, axis: .vertical)
                        .textFieldStyle(.roundedBorder).font(.system(size: 13)).lineLimit(3, reservesSpace: true)
                        .frame(maxWidth: 620)
                    HStack(spacing: 8) {
                        pill("Save", primary: true) { Task { await saveProfile() } }
                        pill("Cancel") { editing = false }
                    }.padding(.top, 4)
                } else {
                    Text(displayName)
                        .font(.system(size: 44, weight: .regular, design: .serif)).foregroundStyle(Color.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("@\(profile.username)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.ink2)
                        if isOwner, let e = auth.user?.email, !e.isEmpty {
                            Text("· \(e)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted)
                        }
                    }
                    if !bioText.isEmpty {
                        Text(bioText)
                            .font(.system(size: 14)).foregroundStyle(Color.ink2).lineSpacing(3)
                            .frame(maxWidth: 620, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) { Rectangle().fill(Color.hair.blended(with: Color.accent, fraction: 0.4)).frame(width: 2) }
                            .padding(.top, 4)
                    }
                }
            }
            Spacer(minLength: 0)

            if isOwner && !editing {
                VStack(alignment: .trailing, spacing: 12) {
                    balanceCard
                    HStack(spacing: 8) {
                        pill("Edit profile") { editNickname = auth.user?.nickname ?? ""; editBio = auth.user?.bio ?? ""; editing = true }
                        pill("Password") { showPassword = true }
                        pill("Upload", primary: true, icon: "plus", action: onUpload)
                    }
                }
            }
        }
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
        .sheet(isPresented: $showPassword) { passwordSheet }
    }

    @ViewBuilder private var avatar: some View {
        let initial = String(displayName.prefix(1)).uppercased()
        Circle().fill(Color.paper2)
            .overlay {
                if let a = avatarURLString, !a.isEmpty, let url = URL(string: a) {
                    CachedAsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Text(initial).font(.system(size: 52, weight: .regular, design: .serif)).foregroundStyle(Color.ink) }
                    .clipShape(Circle())
                } else {
                    Text(initial).font(.system(size: 52, weight: .regular, design: .serif)).foregroundStyle(Color.ink)
                }
            }
            .overlay(Circle().strokeBorder(Color.hair, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if isOwner {
                    Button(action: pickAvatar) {
                        Image(systemName: "camera.fill").font(.system(size: 12))
                            .foregroundStyle(Color.paper).frame(width: 32, height: 32)
                            .background(Circle().fill(Color.ink)).overlay(Circle().strokeBorder(Color.paper, lineWidth: 3))
                    }.buttonStyle(.plain).pointerCursor()
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BALANCE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.0).foregroundStyle(Color.coinLabel)
            HStack(spacing: 10) {
                CoinDisc(size: 32, showSymbol: true)
                Text("\(auth.user?.coins ?? 0)").font(.system(size: 38, weight: .semibold, design: .monospaced)).foregroundStyle(Color.coinValue)
                Text("COINS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.0).foregroundStyle(Color.coinLabel)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [.coinSurfaceStart, .coinSurfaceEnd], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.coinBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 8)
    }

    private func pill(_ label: String, primary: Bool = false, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(primary ? Color.paper : Color.ink)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(primary ? Color.ink : Color.paper))
            .overlay(Capsule().strokeBorder(primary ? Color.ink : Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain).pointerCursor()
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHANGE PASSWORD").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Color.muted)
            SecureField("Current password", text: $oldPw).textFieldStyle(.roundedBorder)
            SecureField("New password (min 8 chars)", text: $newPw).textFieldStyle(.roundedBorder)
            if let e = pwError { Text(e).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { showPassword = false; oldPw = ""; newPw = ""; pwError = nil }
                Button(savingPw ? "Saving…" : "Confirm") { Task { await changePassword() } }
                    .buttonStyle(.borderedProminent).disabled(savingPw || newPw.count < 8)
            }
        }
        .padding(24).frame(width: 360)
    }

    private func saveProfile() async {
        saving = true; defer { saving = false }
        do {
            _ = try await APIClient.shared.updateProfile(nickname: editNickname, bio: editBio)
            await auth.refreshProfile()
            await onChanged()
            editing = false
        } catch {}
    }
    private func changePassword() async {
        guard newPw.count >= 8 else { pwError = "New password must be at least 8 characters."; return }
        savingPw = true; defer { savingPw = false }
        do {
            try await APIClient.shared.changePassword(old: oldPw, new: newPw)
            showPassword = false; oldPw = ""; newPw = ""; pwError = nil
        } catch { pwError = error.localizedDescription }
    }
    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .webP]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : (ext == "webp" ? "image/webp" : "image/jpeg")
        Task {
            do {
                _ = try await APIClient.shared.uploadAvatar(imageData: data, filename: url.lastPathComponent, mime: mime)
                await auth.refreshProfile()
                await onChanged()
            } catch {}
        }
    }

    private func memberSince(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

// ─── Uploads tab: Published list (+ owner Pending list) ──────────
struct AccountUploadsTab: View {
    let username: String
    let isOwner: Bool
    var onWallpaper: (Wallpaper) -> Void
    var onCount: (Int) -> Void
    var onPalette: (String?, String?) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            if isOwner {
                PagedWallpaperGrid(
                    headLabel: "PENDING", emptyText: "", hideWhenEmpty: true,
                    fetch: { cursor, limit in try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, limit: limit, status: "0,5") },
                    onWallpaper: onWallpaper,
                    showProcessing: true
                ).id("pending-\(username)")
            }
            PagedWallpaperGrid(
                headLabel: "PUBLISHED", emptyText: "No published wallpapers yet.",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, limit: limit, status: "1") },
                onWallpaper: onWallpaper, onCount: onCount, onPalette: onPalette
            ).id("pub-\(username)")
        }
    }
}

// ─── Reusable paged wallpaper grid ───────────────────────────────
struct PagedWallpaperGrid: View {
    let headLabel: String
    var emptyText: String = "Nothing here yet."
    var hideWhenEmpty: Bool = false
    var privacyNoun: String? = nil
    var privacyIsPublic: Bool = false
    var onTogglePrivacy: ((Bool) -> Void)? = nil
    let fetch: (_ cursor: Int?, _ limit: Int) async throws -> PaginatedData<Wallpaper>
    var onWallpaper: (Wallpaper) -> Void
    var onCount: (Int) -> Void = { _ in }
    var onPalette: (String?, String?) -> Void = { _, _ in }
    var flagIfNotLocal: Bool = false
    var showProcessing: Bool = false

    @State private var items: [Wallpaper] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var loadError: String?

    private let pageSize = 24
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top)]
    }
    private var gridSpacing: CGFloat { 14 }

    var body: some View {
        Group {
            if hideWhenEmpty && loaded && items.isEmpty && loadError == nil {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let noun = privacyNoun {
                        PrivacyBanner(noun: noun, isPublic: privacyIsPublic) { onTogglePrivacy?(!privacyIsPublic) }
                    }
                    LabelRule(text: "\(headLabel) · \(loaded ? "\(total)" : "…")")

                    if loading && items.isEmpty {
                        WallpaperGridSkeleton(
                            columns: gridColumns,
                            count: 12,
                            spacing: gridSpacing,
                            aspectRatio: 3.0 / 2.0,
                            cornerRadius: 10
                        )
                    } else if let err = loadError, items.isEmpty {
                        RemoteLoadErrorView(message: err) {
                            Task { await loadPage(page) }
                        }
                    } else if items.isEmpty {
                        RemoteEmptyStateView(
                            title: emptyText.isEmpty ? "Nothing here yet." : emptyText,
                            message: "This section will fill in once matching activity appears.",
                            symbol: showProcessing ? "hourglass" : "photo.on.rectangle"
                        )
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                            ForEach(items) { wp in
                                if showProcessing {
                                    PendingUploadTileView(wallpaper: wp)
                                } else {
                                    Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp, flagIfNotLocal: flagIfNotLocal) }.buttonStyle(.plain)
                                }
                            }
                        }
                        PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in Task { await loadPage(p) } }
                        if let err = loadError {
                            HStack(spacing: 10) {
                                Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                                Button("Retry") { Task { await loadPage(page) } }.controlSize(.small)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
        // Re-apply this tab's base mesh tint when it reappears (e.g.
        // switching back to an already-loaded tab).
        .onAppear { if loaded { onPalette(items.first?.colorPalette, items.first?.dominantColor) } }
    }

    private func loadPage(_ p: Int) async {
        guard p >= 1, p <= cursors.count else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data = try await fetch(cursors[p - 1], pageSize)
            items = data.items
            total = data.total ?? data.items.count
            onCount(total)
            onPalette(items.first?.colorPalette, items.first?.dominantColor)
            if data.hasMore, let nc = data.nextCursor, nc > 0 {
                if cursors.count == p { cursors.append(nc) } else if p < cursors.count { cursors[p] = nc }
            }
            page = p; loaded = true
        } catch {
            loadError = error.localizedDescription
            loaded = true
        }
    }
}

// ─── Reusable paged collection grid ──────────────────────────────
struct PagedCollectionGrid: View {
    let headLabel: String
    let fetch: (_ cursor: Int?, _ limit: Int) async throws -> PaginatedData<CollectionItem>
    var onCollection: (CollectionItem) -> Void
    var onCount: (Int) -> Void = { _ in }
    var onPalette: (String?, String?) -> Void = { _, _ in }

    @State private var items: [CollectionItem] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var loadError: String?

    private let pageSize = 12
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }
    private var baseTint: String? { items.first?.recentTiles?.first?.dominantColor ?? items.first?.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabelRule(text: "\(headLabel) · \(loaded ? "\(total)" : "…")")
            if loading && items.isEmpty {
                CollectionGridSkeleton(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24, alignment: .top)],
                    count: 8,
                    spacing: 28
                )
            } else if let err = loadError, items.isEmpty {
                RemoteLoadErrorView(message: err) {
                    Task { await loadPage(page) }
                }
            } else if items.isEmpty {
                RemoteEmptyStateView(
                    title: "No collections yet.",
                    message: "Collections will appear here when this user starts grouping wallpapers into sets.",
                    symbol: "square.grid.2x2"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24, alignment: .top)], spacing: 28) {
                    ForEach(items) { c in
                        Button(action: { onCollection(c) }) { CollectionTileCard(item: c) }.buttonStyle(.plain)
                    }
                }
                PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in Task { await loadPage(p) } }
                if let err = loadError {
                    HStack(spacing: 10) {
                        Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                        Button("Retry") { Task { await loadPage(page) } }.controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
        .onAppear { if loaded { onPalette(nil, baseTint) } }
    }

    private func loadPage(_ p: Int) async {
        guard p >= 1, p <= cursors.count else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data = try await fetch(cursors[p - 1], pageSize)
            items = data.items
            total = data.total ?? data.items.count
            onCount(total)
            onPalette(nil, baseTint)
            if data.hasMore, let nc = data.nextCursor, nc > 0 {
                if cursors.count == p { cursors.append(nc) } else if p < cursors.count { cursors[p] = nc }
            }
            page = p; loaded = true
        } catch {
            loadError = error.localizedDescription
            loaded = true
        }
    }
}

// ─── Coin ledger tab ─────────────────────────────────────────────
struct LedgerTab: View {
    var onCount: (Int) -> Void = { _ in }
    var onPalette: (String?, String?) -> Void = { _, _ in }

    @State private var txs: [CoinTransaction] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var loadError: String?
    @State private var auth = AuthService.shared

    private let pageSize = 12
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }
    private var earned: Int { txs.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    private var spent: Int { txs.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                coinSummary("BALANCE", "\(auth.user?.coins ?? 0)", "Lifetime balance")
                summary("EARNED", "+\(earned)", "This page", tint: Color(hex: "#3e9e5e"))
                summary("SPENT", "−\(spent)", "This page", tint: Color.ink2)
                summary("NEXT EARN", "+1", "Per upload", tint: Color.ink2)
            }
            LabelRule(text: "LEDGER · \(loaded ? "\(total)" : "…")")
            if loading && txs.isEmpty {
                LedgerRowsSkeleton(rows: 4)
            } else if let err = loadError, txs.isEmpty {
                RemoteLoadErrorView(title: "Could not load transactions", message: err) {
                    Task { await loadPage(page) }
                }
            } else if txs.isEmpty {
                RemoteEmptyStateView(
                    title: "No transactions yet.",
                    message: "Coin activity will show here after uploads, trades, and system grants.",
                    symbol: "creditcard"
                )
            } else {
                VStack(spacing: 8) { ForEach(txs) { tx in ledgerRow(tx) } }
                PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in Task { await loadPage(p) } }
                if let err = loadError {
                    HStack(spacing: 10) {
                        Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                        Button("Retry") { Task { await loadPage(page) } }.controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
        // No imagery in the ledger — keep the warm brand mesh.
        .onAppear { onPalette(nil, nil) }
    }

    private func summary(_ kicker: String, _ value: String, _ sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.6).foregroundStyle(Color.muted)
            Text(value).font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(tint)
            Text(sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.paper.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hair, lineWidth: 1))
    }

    private func coinSummary(_ kicker: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                CoinDisc(size: 18)
                Text(kicker)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.coinLabel)
            }
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.coinValue)
                .monospacedDigit()
            Text(sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.coinLabel)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [.coinSurfaceStart, .coinSurfaceEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.coinBorder, lineWidth: 1))
    }

    private func ledgerRow(_ tx: CoinTransaction) -> some View {
        let earn = tx.amount >= 0
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(earn ? Color(hex: "#3e9e5e").opacity(0.16) : Color.paper2)
                Text(glyph(tx.txType)).font(.system(size: 14)).foregroundStyle(earn ? Color(hex: "#3e9e5e") : Color.ink2)
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(ledgerLabel(tx)).font(.system(size: 13)).foregroundStyle(Color.ink)
                Text(relativeCoinTime(tx.createdAt)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted)
            }
            Spacer()
            Text(earn ? "+\(tx.amount)" : "\(tx.amount)")
                .font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(earn ? Color(hex: "#3e9e5e") : Color.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.paper.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hair, lineWidth: 1))
    }

    private func glyph(_ type: String) -> String {
        switch type {
        case "register_bonus": "✨"
        case "upload_reward": "↑"
        case "download_cost", "download_spent": "↓"
        case "download_earned", "download_received": "★"
        default: "•"
        }
    }
    private func ledgerLabel(_ tx: CoinTransaction) -> String {
        let map: [String: String] = [
            "register_bonus": "Welcome bonus", "upload_reward": "Upload reward",
            "download_cost": "Download", "download_spent": "Download",
            "download_earned": "Download received", "download_received": "Download received",
            "admin_grant": "Admin grant",
        ]
        if let l = map[tx.txType] { return l }
        return tx.description.isEmpty ? tx.txType : tx.description
    }

    private func loadPage(_ p: Int) async {
        guard p >= 1, p <= cursors.count else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data = try await APIClient.shared.fetchCoinTransactions(cursor: cursors[p - 1], limit: pageSize)
            txs = data.items
            total = data.total ?? data.items.count
            onCount(total)
            if data.hasMore, let nc = data.nextCursor, nc > 0 {
                if cursors.count == p { cursors.append(nc) } else if p < cursors.count { cursors[p] = nc }
            }
            page = p; loaded = true
        } catch {
            loadError = error.localizedDescription
            loaded = true
        }
    }
}

// ─── Per-tab privacy banner (owner) ──────────────────────────────
struct PrivacyBanner: View {
    let noun: String
    let isPublic: Bool
    var onToggle: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(Color.paper2); Image(systemName: isPublic ? "globe" : "lock").font(.system(size: 13)).foregroundStyle(Color.ink2) }
                .frame(width: 36, height: 36).overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your \(noun) are \(isPublic ? "public" : "private")").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
                Text(isPublic ? "Anyone can see this list on your profile." : "Only you can see this list.")
                    .font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer()
            Button(action: onToggle) {
                Text(isPublic ? "Make private" : "Make public").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.paper)).overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
            }.buttonStyle(.plain).pointerCursor()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.paper.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hair, lineWidth: 1))
    }
}

// ─── Pagination control (web Pagination.tsx) ─────────────────────
struct PageBar: View {
    let current: Int
    let totalPages: Int
    let maxReachable: Int
    var onChange: (Int) -> Void

    private var pages: [Int?] {
        if totalPages <= 7 { return Array(1...max(totalPages, 1)).map { $0 } }
        var out: [Int?] = [1]
        if current > 3 { out.append(nil) }
        for p in max(2, current - 1)...min(totalPages - 1, current + 1) { out.append(p) }
        if current < totalPages - 2 { out.append(nil) }
        out.append(totalPages)
        return out
    }

    var body: some View {
        if totalPages > 1 {
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    navButton("PREV", enabled: current > 1) { onChange(current - 1) }
                    HStack(spacing: 4) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, p in
                            if let p { pageButton(p) }
                            else { Text("…").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted).frame(minWidth: 24) }
                        }
                    }
                    navButton("NEXT", enabled: current < totalPages && current < maxReachable) { onChange(current + 1) }
                }
                Text("PAGE \(current) OF \(totalPages)").font(.system(size: 10, design: .monospaced)).tracking(1.2).foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 8)
        }
    }

    private func navButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.0)
                .foregroundStyle(enabled ? Color.ink2 : Color.muted.opacity(0.5))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(Color.paper)).overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
        }.buttonStyle(.plain).disabled(!enabled).pointerCursor()
    }
    private func pageButton(_ p: Int) -> some View {
        let isCurrent = p == current
        let reachable = p <= maxReachable
        return Button(action: { if reachable && !isCurrent { onChange(p) } }) {
            Text("\(p)").font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isCurrent ? Color.paper : (reachable ? Color.ink2 : Color.muted.opacity(0.4)))
                .frame(minWidth: 32, minHeight: 32).background(Capsule().fill(isCurrent ? Color.ink : Color.clear))
        }.buttonStyle(.plain).disabled(!reachable || isCurrent).pointerCursor()
    }
}

// ─── Section-head rule (web .label-rule) ─────────────────────────
struct LabelRule: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.6).foregroundStyle(Color.muted)
            Rectangle().fill(Color.hair).frame(height: 1)
        }
    }
}

private func relativeCoinTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = f.date(from: iso) ?? plain.date(from: iso) else { return "" }
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    if diff < 3600 { return "\(Int(diff / 60)) min ago" }
    if diff < 86400 { return "\(Int(diff / 3600)) hr ago" }
    let days = Int(diff / 86400)
    if days < 30 { return "\(days)d ago" }
    let months = days / 30
    if months < 12 { return "\(months)mo ago" }
    return "\(months / 12)y ago"
}
