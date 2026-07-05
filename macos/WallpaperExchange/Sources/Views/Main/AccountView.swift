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

    init(
        username: String,
        initialTab: AccountTab = .uploads,
        onWallpaper: @escaping (Wallpaper) -> Void,
        onCollection: @escaping (CollectionItem) -> Void,
        onUpload: @escaping () -> Void = {}
    ) {
        self.username = username
        self.initialTab = initialTab
        self.onWallpaper = onWallpaper
        self.onCollection = onCollection
        self.onUpload = onUpload
        _tab = State(initialValue: initialTab)
    }

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
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    SkeletonLine(width: 104, height: 38, cornerRadius: 6)
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
            accountContentSkeleton
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var accountContentSkeleton: some View {
        switch tab {
        case .collections:
            CollectionGridSkeleton(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24, alignment: .top)],
                count: 8,
                spacing: 28
            )
        case .ledger:
            LedgerRowsSkeleton(rows: 4)
        default:
            WallpaperGridSkeleton(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top)],
                count: 12
            )
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
    // GlassKit segmented pill (liquid selection droplet) instead of
    // the old underline tabs — matches the window chrome family.
    // Full page width: segments share the row equally within the
    // page's fixed side gutters.
    private var tabBar: some View {
        GlassSegmented(
            segments: tabs.map {
                GlassSegment(id: $0, label: $0.label, icon: $0.icon, badge: counts[$0].map { "\($0)" })
            },
            selection: $tab,
            compact: true,
            fullWidth: true
        )
        .padding(.top, 18)
        .padding(.bottom, 10)
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
                headLabel: L10n.account.headCreated,
                fetch: { cursor, limit in try await APIClient.shared.fetchUserCollections(idOrUsername: username, cursor: cursor, limit: limit) },
                onCollection: onCollection,
                onCount: { counts[.collections] = $0 },
                onPalette: applyMesh,
                showsAutoPlayControls: isOwner
            ).id("collections-\(username)")
        case .favorites:
            wallpaperList(.favorites, head: L10n.account.headFavorites, empty: L10n.account.emptyFavorites,
                          isPublic: auth.user?.favoritesPublic ?? false, noun: L10n.account.nounFavorites,
                          fetch: { c, l in try await APIClient.shared.fetchUserFavorites(username: username, cursor: c, limit: l) },
                          toggle: { v in Task { try? await APIClient.shared.updatePrivacy(favoritesPublic: v); await auth.refreshProfile() } })
        case .likes:
            wallpaperList(.likes, head: L10n.account.headLikes, empty: L10n.account.emptyLikes,
                          isPublic: auth.user?.likesPublic ?? false, noun: L10n.account.nounLikes,
                          fetch: { c, l in try await APIClient.shared.fetchUserLikes(username: username, cursor: c, limit: l) },
                          toggle: { v in Task { try? await APIClient.shared.updatePrivacy(likesPublic: v); await auth.refreshProfile() } })
        case .downloads:
            VStack(alignment: .leading, spacing: 22) {
                wallpaperList(.downloads, head: L10n.account.headDownloads, empty: L10n.account.emptyDownloads,
                              isPublic: auth.user?.downloadsPublic ?? false, noun: L10n.account.nounDownloads,
                              fetch: { c, l in try await APIClient.shared.fetchUserDownloads(username: username, cursor: c, limit: l) },
                              toggle: { v in Task { try? await APIClient.shared.updatePrivacy(downloadsPublic: v); await auth.refreshProfile() } },
                              flagIfNotLocal: true)
            }
        case .ledger:
            LedgerTab(onCount: { counts[.ledger] = $0 }, onPalette: applyMesh)
        }
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
        ).id("\(t.rawValue)-\(username)")
    }
}

enum AccountTab: String, Hashable {
    case settings, uploads, collections, favorites, likes, downloads, ledger
    var label: String {
        switch self {
        case .settings: L10n.account.tabSettings
        case .uploads: L10n.account.tabUploads
        case .collections: L10n.account.tabCollections
        case .favorites: L10n.account.tabFavorites
        case .likes: L10n.account.tabLikes
        case .downloads: L10n.account.tabDownloads
        case .ledger: L10n.account.tabLedger
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
                Text(L10n.account.contributorSince(memberSince(profile.createdAt)).uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(Color.muted)

                if editing {
                    TextField(L10n.account.nicknamePlaceholder, text: $editNickname)
                        .textFieldStyle(.plain).font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ink)
                    TextField(L10n.account.bioPlaceholder, text: $editBio, axis: .vertical)
                        .textFieldStyle(.roundedBorder).font(.system(size: 13)).lineLimit(3, reservesSpace: true)
                        .frame(maxWidth: 620)
                    HStack(spacing: 8) {
                        pill(L10n.account.save, primary: true) { Task { await saveProfile() } }
                        pill(L10n.common.cancel) { editing = false }
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
                        pill(L10n.account.editProfile) { editNickname = auth.user?.nickname ?? ""; editBio = auth.user?.bio ?? ""; editing = true }
                        pill(L10n.account.password) { showPassword = true }
                        pill(L10n.account.upload, primary: true, icon: "plus", action: onUpload)
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
            Text(L10n.account.balanceKicker).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.0).foregroundStyle(Color.coinLabel)
            HStack(spacing: 10) {
                CoinDisc(size: 32, showSymbol: true)
                Text("\(auth.user?.coins ?? 0)").font(.system(size: 38, weight: .semibold, design: .monospaced)).foregroundStyle(Color.coinValue)
                Text(L10n.account.coinsUnit).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.0).foregroundStyle(Color.coinLabel)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [.coinSurfaceStart, .coinSurfaceEnd], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.coinBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 8)
    }

    private func pill(_ label: String, primary: Bool = false, icon: String? = nil, action: @escaping () -> Void) -> some View {
        GlassCapsuleButton(
            title: label,
            icon: icon,
            style: primary ? .accent : .glass(.light),
            height: 30,
            fontSize: 12,
            action: action
        )
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.account.changePasswordTitle).font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Color.muted)
            SecureField(L10n.account.currentPassword, text: $oldPw).textFieldStyle(.roundedBorder)
            SecureField(L10n.account.newPasswordPlaceholder, text: $newPw).textFieldStyle(.roundedBorder)
            if let e = pwError { Text(e).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.common.cancel) { showPassword = false; oldPw = ""; newPw = ""; pwError = nil }
                Button(savingPw ? L10n.account.saving : L10n.common.confirm) { Task { await changePassword() } }
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
        guard newPw.count >= 8 else { pwError = L10n.account.newPasswordTooShort; return }
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
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.account.dateLocaleID)
        f.dateFormat = L10n.account.memberSinceFormatLong
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
                    headLabel: L10n.account.headPending, emptyText: "", hideWhenEmpty: true,
                    fetch: { cursor, limit in try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, limit: limit, status: "0,5") },
                    onWallpaper: onWallpaper,
                    showProcessing: true
                ).id("pending-\(username)")
            }
            PagedWallpaperGrid(
                headLabel: L10n.account.headPublished, emptyText: L10n.account.emptyPublished,
                fetch: { cursor, limit in try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, limit: limit, status: "1") },
                onWallpaper: onWallpaper, onCount: onCount, onPalette: onPalette
            ).id("pub-\(username)")
        }
    }
}

// ─── Reusable paged wallpaper grid ───────────────────────────────
struct PagedWallpaperGrid: View {
    let headLabel: String
    var emptyText: String = L10n.account.nothingHere
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
                            title: emptyText.isEmpty ? L10n.account.nothingHere : emptyText,
                            message: L10n.account.emptySectionMessage,
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
                                Button(L10n.common.retry) { Task { await loadPage(page) } }.controlSize(.small)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
        // Entering the tab shows the default brand mesh — not the first
        // card's color. The mesh only shifts when a tile is hovered
        // (MainGridTile drives PaletteEnv directly).
        .onAppear { onPalette(nil, nil) }
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
    var showsAutoPlayControls: Bool = false

    @State private var manager = WallpaperManager.shared
    @State private var items: [CollectionItem] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = true
    @State private var loaded = false
    @State private var loadError: String?
    @State private var autoPlayBusyCollectionID: Int?
    @State private var autoPlayError: String?
    @State private var pendingAutoPlayCollection: CollectionItem?
    @State private var pendingAutoPlayWallpapers: [Wallpaper] = []
    @State private var pendingMissingCount = 0
    @State private var showAutoPlayDownloadPrompt = false
    @State private var hoveredAutoPlayCollectionID: Int?

    private let pageSize = 12
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabelRule(text: "\(headLabel) · \(loaded ? "\(total)" : "…")")
            if showsAutoPlayControls {
                autoPlayStatusPanel
            }
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
                    title: L10n.account.emptyCollectionsTitle,
                    message: L10n.account.emptyCollectionsMessage,
                    symbol: "square.grid.2x2"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24, alignment: .top)], spacing: 28) {
                    ForEach(items) { c in
                        collectionCell(c)
                    }
                }
                PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in Task { await loadPage(p) } }
                if let err = loadError {
                    HStack(spacing: 10) {
                        Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                        Button(L10n.common.retry) { Task { await loadPage(page) } }.controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
        // Default brand mesh on enter; hovering a collection card tints it.
        .onAppear { onPalette(nil, nil) }
        .confirmationDialog(
            L10n.account.collectionAutoPlayDownloadTitle,
            isPresented: $showAutoPlayDownloadPrompt,
            titleVisibility: .visible
        ) {
            Button(L10n.account.collectionAutoPlayDownloadConfirm) {
                Task { await confirmAutoPlayDownload() }
            }
            Button(L10n.common.cancel, role: .cancel) {
                clearPendingAutoPlay()
            }
        } message: {
            Text(L10n.account.collectionAutoPlayDownloadMessage(pendingMissingCount))
        }
    }

    private var autoPlayStatusPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: manager.autoRotateCollectionID == nil ? "shuffle" : "rectangle.stack.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(manager.autoRotateCollectionID == nil ? Color.muted : Color.accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.paper2))
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.autoRotateCollectionTitle.map(L10n.account.collectionAutoPlayStatus)
                     ?? L10n.account.collectionAutoPlayFallback)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(2)
                if let autoPlayError {
                    Text(autoPlayError)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.warn)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if manager.autoRotateCollectionID != nil {
                GlassCapsuleButton(title: L10n.account.collectionAutoPlayStop, height: 28, fontSize: 11) {
                    autoPlayError = nil
                    manager.clearAutoRotateCollection()
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.paper.opacity(0.52)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.hair.opacity(0.85), lineWidth: 1))
    }

    private func collectionCell(_ collection: CollectionItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { onCollection(collection) }) {
                CollectionTileCard(item: collection)
            }
            .buttonStyle(.plain)

            if shouldShowAutoPlayButton(for: collection) {
                autoPlayButton(collection)
                    .padding(.top, 12)
                    .padding(.trailing, 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredAutoPlayCollectionID = hovering ? collection.id : nil
        }
        .animation(.easeOut(duration: 0.16), value: hoveredAutoPlayCollectionID)
    }

    private func shouldShowAutoPlayButton(for collection: CollectionItem) -> Bool {
        guard showsAutoPlayControls else { return false }
        return hoveredAutoPlayCollectionID == collection.id || autoPlayBusyCollectionID == collection.id
    }

    private func autoPlayButton(_ collection: CollectionItem) -> some View {
        let isActive = manager.autoRotateCollectionID == collection.id
        let isBusy = autoPlayBusyCollectionID == collection.id
        return Button {
            autoPlayError = nil
            if isActive {
                manager.clearAutoRotateCollection()
            } else {
                Task { await prepareAutoPlay(collection) }
            }
        } label: {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.68)
                } else {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "shuffle")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isBusy
                     ? L10n.account.collectionAutoPlayPreparing
                     : (isActive ? L10n.account.collectionAutoPlayActive : L10n.account.collectionAutoPlay))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.accentInk : Color.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Color.accentSoft.opacity(0.94) : Color.paper.opacity(0.92))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.accent.opacity(0.42) : Color.hair.opacity(0.86), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || (autoPlayBusyCollectionID != nil && !isBusy))
        .help(isActive ? L10n.account.collectionAutoPlayStop : L10n.account.collectionAutoPlay)
    }

    private func prepareAutoPlay(_ collection: CollectionItem) async {
        guard autoPlayBusyCollectionID == nil else { return }
        autoPlayBusyCollectionID = collection.id
        autoPlayError = nil
        defer { autoPlayBusyCollectionID = nil }

        do {
            let wallpapers = try await manager.fetchAllCollectionWallpapers(collectionID: collection.id)
            let missing = manager.missingLocalWallpapers(in: wallpapers)
            if missing.isEmpty {
                try await manager.setAutoRotateCollection(collection, wallpapers: wallpapers, downloadMissing: false)
            } else {
                pendingAutoPlayCollection = collection
                pendingAutoPlayWallpapers = wallpapers
                pendingMissingCount = missing.count
                showAutoPlayDownloadPrompt = true
            }
        } catch {
            autoPlayError = error.localizedDescription
        }
    }

    private func confirmAutoPlayDownload() async {
        guard let collection = pendingAutoPlayCollection else { return }
        let wallpapers = pendingAutoPlayWallpapers
        clearPendingAutoPlay(keepPrompt: false)
        autoPlayBusyCollectionID = collection.id
        autoPlayError = nil
        defer { autoPlayBusyCollectionID = nil }

        do {
            try await manager.setAutoRotateCollection(collection, wallpapers: wallpapers, downloadMissing: true)
        } catch {
            autoPlayError = error.localizedDescription
        }
    }

    private func clearPendingAutoPlay(keepPrompt: Bool = false) {
        pendingAutoPlayCollection = nil
        pendingAutoPlayWallpapers = []
        pendingMissingCount = 0
        if !keepPrompt {
            showAutoPlayDownloadPrompt = false
        }
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
                coinSummary(L10n.account.balanceKicker, "\(auth.user?.coins ?? 0)", L10n.account.lifetimeBalance)
                summary(L10n.account.kickerEarned, "+\(earned)", L10n.account.thisPage, tint: Color(hex: "#3e9e5e"))
                summary(L10n.account.kickerSpent, "−\(spent)", L10n.account.thisPage, tint: Color.ink2)
                summary(L10n.account.kickerNextEarn, "+1", L10n.account.perUpload, tint: Color.ink2)
            }
            LabelRule(text: "\(L10n.account.headLedger) · \(loaded ? "\(total)" : "…")")
            if loading && txs.isEmpty {
                LedgerRowsSkeleton(rows: 4)
            } else if let err = loadError, txs.isEmpty {
                RemoteLoadErrorView(title: L10n.account.txErrorTitle, message: err) {
                    Task { await loadPage(page) }
                }
            } else if txs.isEmpty {
                RemoteEmptyStateView(
                    title: L10n.account.txEmptyTitle,
                    message: L10n.account.txEmptyMessage,
                    symbol: "creditcard"
                )
            } else {
                VStack(spacing: 8) { ForEach(txs) { tx in ledgerRow(tx) } }
                PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in Task { await loadPage(p) } }
                if let err = loadError {
                    HStack(spacing: 10) {
                        Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                        Button(L10n.common.retry) { Task { await loadPage(page) } }.controlSize(.small)
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
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hair, lineWidth: 1))
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
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.coinSurfaceStart, .coinSurfaceEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.coinBorder, lineWidth: 1))
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
            "register_bonus": L10n.account.txWelcomeBonus, "upload_reward": L10n.account.txUploadReward,
            "download_cost": L10n.account.txDownload, "download_spent": L10n.account.txDownload,
            "download_earned": L10n.account.txDownloadReceived, "download_received": L10n.account.txDownloadReceived,
            "admin_grant": L10n.account.txAdminGrant,
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
                Text(L10n.account.privacyStatus(noun, isPublic)).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
                Text(isPublic ? L10n.account.privacyPublicDesc : L10n.account.privacyPrivateDesc)
                    .font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer()
            GlassCapsuleButton(
                title: isPublic ? L10n.account.makePrivate : L10n.account.makePublic,
                height: 30,
                fontSize: 12,
                action: onToggle
            )
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hair, lineWidth: 1))
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
                    navButton(L10n.account.pagePrev, enabled: current > 1) { onChange(current - 1) }
                    HStack(spacing: 4) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, p in
                            if let p { pageButton(p) }
                            else { Text("…").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted).frame(minWidth: 24) }
                        }
                    }
                    navButton(L10n.account.pageNext, enabled: current < totalPages && current < maxReachable) { onChange(current + 1) }
                }
                Text(L10n.account.pageOf(current, totalPages)).font(.system(size: 10, design: .monospaced)).tracking(1.2).foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 8)
        }
    }

    private func navButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        GlassCapsuleButton(title: label, height: 32, fontSize: 11, action: action)
            .disabled(!enabled)
    }
    private func pageButton(_ p: Int) -> some View {
        let isCurrent = p == current
        let reachable = p <= maxReachable
        return GlassChip(label: "\(p)", active: isCurrent) {
            if reachable && !isCurrent { onChange(p) }
        }
        .disabled(!reachable || isCurrent)
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
    if diff < 60 { return L10n.account.justNow }
    if diff < 3600 { return L10n.account.minAgo(Int(diff / 60)) }
    if diff < 86400 { return L10n.account.hrAgo(Int(diff / 3600)) }
    let days = Int(diff / 86400)
    if days < 30 { return L10n.account.daysAgo(days) }
    let months = days / 30
    if months < 12 { return L10n.account.monthsAgo(months) }
    return L10n.account.yearsAgo(months / 12)
}
