import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Unified account / profile page — the Mac port of the web ProfilePage.
// One editorial header + an underline tab bar (.ptabs) + per-tab paged
// content. For the signed-in owner the tab list gains a Mac-only
// "Settings" tab (first) plus the owner-only Downloads / Coin ledger
// tabs and account editing. Viewing someone else shows the public
// subset (Uploads / Collections / Favorites / Likes). All grids use
// prev/next pagination (no infinite scroll) and the same web-matching
// cards as the rest of the app.
struct AccountView: View {
    let username: String
    var initialTab: AccountTab = .uploads
    var onWallpaper: (Wallpaper) -> Void
    var onCollection: (CollectionItem) -> Void

    @State private var auth = AuthService.shared
    @State private var profile: PublicProfile?
    @State private var loadError: String?
    @State private var tab: AccountTab = .uploads
    @State private var didInit = false

    private var isOwner: Bool {
        guard let me = auth.user else { return false }
        return me.username == username
    }

    private var tabs: [AccountTab] {
        if isOwner {
            return [.settings, .uploads, .collections, .favorites, .likes, .downloads, .ledger]
        }
        return [.uploads, .collections, .favorites, .likes]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let p = profile {
                    header(p)
                    tabBar
                    content(p)
                        .padding(.top, 26)
                } else if let err = loadError {
                    Text(err).font(.sans12).foregroundStyle(Color.muted).padding(.top, 80)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1180).frame(maxWidth: .infinity, alignment: .center)
        }
        .task(id: username) {
            if !didInit { tab = initialTab; didInit = true }
            await loadProfile()
        }
        // Sidebar re-routes (My Uploads → My Likes …) keep the same
        // username, so the task above won't refire — track initialTab
        // directly so the selected tab follows the sidebar.
        .onChange(of: initialTab) { _, new in tab = new }
    }

    private func loadProfile() async {
        loadError = nil
        do { profile = try await APIClient.shared.fetchPublicProfile(username: username) }
        catch { loadError = error.localizedDescription }
    }

    // ─── Header ──────────────────────────────────────────────────
    private func header(_ p: PublicProfile) -> some View {
        HStack(alignment: .top, spacing: 28) {
            avatar(p).frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 8) {
                Text("Contributor · Member since \(memberSince(p.createdAt))".uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.8).foregroundStyle(Color.muted)
                Text(p.nickname?.isEmpty == false ? p.nickname! : p.username)
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("@\(p.username)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.ink2)
                    if isOwner, let e = auth.user?.email, !e.isEmpty {
                        Text("· \(e)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted)
                    }
                }
                if let bio = p.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 14)).foregroundStyle(Color.ink2)
                        .lineSpacing(3).frame(maxWidth: 620, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.hair.blended(with: Color.accent, fraction: 0.4)).frame(width: 2)
                        }
                        .padding(.top, 4)
                }
                statRow(p).padding(.top, 8)
            }
            Spacer(minLength: 0)

            if isOwner { balanceCard }
        }
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
    }

    @ViewBuilder private func avatar(_ p: PublicProfile) -> some View {
        let initial = String((p.nickname?.isEmpty == false ? p.nickname! : p.username).prefix(1)).uppercased()
        Circle().fill(Color.paper2)
            .overlay {
                if let a = p.avatarURL, !a.isEmpty, let url = URL(string: a) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(initial).font(.system(size: 52, weight: .regular, design: .serif)).foregroundStyle(Color.ink)
                    }
                    .clipShape(Circle())
                } else {
                    Text(initial).font(.system(size: 52, weight: .regular, design: .serif)).foregroundStyle(Color.ink)
                }
            }
            .overlay(Circle().strokeBorder(Color.hair, lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private func statRow(_ p: PublicProfile) -> some View {
        HStack(spacing: 28) {
            stat("UPLOADS", p.uploadCount ?? 0)
            stat("DOWNLOADS", p.downloadCount ?? 0)
            stat("LIKES", p.likeCount ?? 0)
            stat("COLLECTIONS", p.collectionCount ?? 0)
        }
    }
    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.6).foregroundStyle(Color.muted)
            Text("\(value)").font(.system(size: 26, weight: .regular, design: .serif)).foregroundStyle(Color.ink)
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BALANCE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.0).foregroundStyle(Color.muted)
            HStack(spacing: 10) {
                Circle().fill(
                    RadialGradient(colors: [Color(hex: "#f6d68a"), Color(hex: "#d8a23a")], center: .topLeading, startRadius: 1, endRadius: 30)
                ).frame(width: 32, height: 32)
                .overlay(Image(systemName: "circle.hexagongrid.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.9)))
                Text("\(auth.user?.coins ?? 0)").font(.system(size: 38, weight: .semibold, design: .monospaced)).foregroundStyle(Color.ink)
                Text("COINS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.0).foregroundStyle(Color.muted)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#fbf2dd").opacity(0.92), Color(hex: "#f3e2c2").opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: "#e6c48a"), lineWidth: 1))
    }

    // ─── Tab bar (web .ptabs) ────────────────────────────────────
    private var tabBar: some View {
        HStack(spacing: 28) {
            ForEach(tabs, id: \.self) { t in
                Button(action: { tab = t }) {
                    HStack(spacing: 8) {
                        Image(systemName: t.icon).font(.system(size: 12, weight: .medium))
                        Text(t.label).font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(tab == t ? Color.ink : Color.muted)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(tab == t ? Color.ink : Color.clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
    }

    // ─── Tab content ─────────────────────────────────────────────
    @ViewBuilder private func content(_ p: PublicProfile) -> some View {
        switch tab {
        case .settings:
            AccountSettingsTab()
        case .uploads:
            AccountUploadsTab(username: username, isOwner: isOwner, onWallpaper: onWallpaper)
        case .collections:
            PagedCollectionGrid(
                headLabel: "CREATED",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserCollections(idOrUsername: username, cursor: cursor, limit: limit) },
                onCollection: onCollection
            )
            .id("collections-\(username)")
        case .favorites:
            PagedWallpaperGrid(
                headLabel: "FAVORITES", emptyText: "No favorites yet.",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserFavorites(username: username, cursor: cursor, limit: limit) },
                onWallpaper: onWallpaper
            )
            .id("fav-\(username)")
        case .likes:
            PagedWallpaperGrid(
                headLabel: "LIKES", emptyText: "No likes yet.",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserLikes(username: username, cursor: cursor, limit: limit) },
                onWallpaper: onWallpaper
            )
            .id("like-\(username)")
        case .downloads:
            PagedWallpaperGrid(
                headLabel: "DOWNLOADS", emptyText: "No downloads yet.",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserDownloads(username: username, cursor: cursor, limit: limit) },
                onWallpaper: onWallpaper
            )
            .id("dl-\(username)")
        case .ledger:
            LedgerTab()
        }
    }

    private func memberSince(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
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

// ─── Uploads tab: Published list (+ owner Pending list) ──────────
struct AccountUploadsTab: View {
    let username: String
    let isOwner: Bool
    var onWallpaper: (Wallpaper) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            if isOwner {
                PagedWallpaperGrid(
                    headLabel: "PENDING", emptyText: "",
                    hideWhenEmpty: true,
                    fetch: { cursor, limit in try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, limit: limit, status: "0,5") },
                    onWallpaper: onWallpaper
                )
                .id("pending-\(username)")
            }
            PagedWallpaperGrid(
                headLabel: "PUBLISHED", emptyText: "No published wallpapers yet.",
                fetch: { cursor, limit in try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, limit: limit, status: "1") },
                onWallpaper: onWallpaper
            )
            .id("pub-\(username)")
        }
    }
}

// ─── Reusable paged wallpaper grid ───────────────────────────────
struct PagedWallpaperGrid: View {
    let headLabel: String
    var emptyText: String = "Nothing here yet."
    var hideWhenEmpty: Bool = false
    let fetch: (_ cursor: Int?, _ limit: Int) async throws -> PaginatedData<Wallpaper>
    var onWallpaper: (Wallpaper) -> Void

    @State private var items: [Wallpaper] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false

    private let pageSize = 24
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }

    var body: some View {
        Group {
            if hideWhenEmpty && loaded && items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    LabelRule(text: "\(headLabel) · \(loaded ? "\(total)" : "…")")

                    if loading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if items.isEmpty {
                        Text(emptyText).font(.sans13).foregroundStyle(Color.muted).padding(.vertical, 24)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top)], spacing: 14) {
                            ForEach(items) { wp in
                                Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp) }
                                    .buttonStyle(.plain)
                            }
                        }
                        PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in
                            Task { await loadPage(p) }
                        }
                    }
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
    }

    private func loadPage(_ p: Int) async {
        guard p >= 1, p <= cursors.count else { return }
        loading = true; defer { loading = false }
        do {
            let cur = cursors[p - 1]
            let data = try await fetch(cur, pageSize)
            items = data.items
            total = data.total ?? data.items.count
            if data.hasMore, let nc = data.nextCursor, nc > 0 {
                if cursors.count == p { cursors.append(nc) } else if p < cursors.count { cursors[p] = nc }
            }
            page = p
            loaded = true
        } catch {
            loaded = true
        }
    }
}

// ─── Reusable paged collection grid ──────────────────────────────
struct PagedCollectionGrid: View {
    let headLabel: String
    let fetch: (_ cursor: Int?, _ limit: Int) async throws -> PaginatedData<CollectionItem>
    var onCollection: (CollectionItem) -> Void

    @State private var items: [CollectionItem] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false

    private let pageSize = 12
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabelRule(text: "\(headLabel) · \(loaded ? "\(total)" : "…")")

            if loading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if items.isEmpty {
                Text("No collections yet.").font(.sans13).foregroundStyle(Color.muted).padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24, alignment: .top)], spacing: 28) {
                    ForEach(items) { c in
                        Button(action: { onCollection(c) }) { CollectionTileCard(item: c) }
                            .buttonStyle(.plain)
                    }
                }
                PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in
                    Task { await loadPage(p) }
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
    }

    private func loadPage(_ p: Int) async {
        guard p >= 1, p <= cursors.count else { return }
        loading = true; defer { loading = false }
        do {
            let cur = cursors[p - 1]
            let data = try await fetch(cur, pageSize)
            items = data.items
            total = data.total ?? data.items.count
            if data.hasMore, let nc = data.nextCursor, nc > 0 {
                if cursors.count == p { cursors.append(nc) } else if p < cursors.count { cursors[p] = nc }
            }
            page = p
            loaded = true
        } catch { loaded = true }
    }
}

// ─── Coin ledger tab ─────────────────────────────────────────────
struct LedgerTab: View {
    @State private var txs: [CoinTransaction] = []
    @State private var page = 1
    @State private var cursors: [Int?] = [nil]
    @State private var total = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var auth = AuthService.shared

    private let pageSize = 12
    private var totalPages: Int { total > 0 ? Int(ceil(Double(total) / Double(pageSize))) : max(cursors.count, 1) }
    private var earned: Int { txs.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    private var spent: Int { txs.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary cards
            HStack(spacing: 12) {
                summary("BALANCE", "\(auth.user?.coins ?? 0)", "Lifetime balance", tint: Color(hex: "#d8a23a"))
                summary("EARNED", "+\(earned)", "This page", tint: Color(hex: "#3e9e5e"))
                summary("SPENT", "−\(spent)", "This page", tint: Color.ink2)
                summary("NEXT EARN", "+1", "Per upload", tint: Color.ink2)
            }

            LabelRule(text: "LEDGER · \(loaded ? "\(total)" : "…")")

            if loading && txs.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if txs.isEmpty {
                Text("No transactions yet.").font(.sans13).foregroundStyle(Color.muted).padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(txs) { tx in ledgerRow(tx) }
                }
                PageBar(current: page, totalPages: totalPages, maxReachable: cursors.count) { p in
                    Task { await loadPage(p) }
                }
            }
        }
        .task { if !loaded { await loadPage(1) } }
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

    private func ledgerRow(_ tx: CoinTransaction) -> some View {
        let earn = tx.amount >= 0
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(earn ? Color(hex: "#3e9e5e").opacity(0.16) : Color.paper2)
                Text(glyph(tx.txType)).font(.system(size: 14)).foregroundStyle(earn ? Color(hex: "#3e9e5e") : Color.ink2)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(ledgerLabel(tx)).font(.system(size: 13)).foregroundStyle(Color.ink)
                Text(relativeCoinTime(tx.createdAt)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.muted)
            }
            Spacer()
            Text(earn ? "+\(tx.amount)" : "\(tx.amount)")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(earn ? Color(hex: "#3e9e5e") : Color.ink2)
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
            "register_bonus": "Welcome bonus",
            "upload_reward": "Upload reward",
            "download_cost": "Download",
            "download_spent": "Download",
            "download_earned": "Download received",
            "download_received": "Download received",
            "admin_grant": "Admin grant",
        ]
        if let l = map[tx.txType] { return l }
        return tx.description.isEmpty ? tx.txType : tx.description
    }

    private func loadPage(_ p: Int) async {
        guard p >= 1, p <= cursors.count else { return }
        loading = true; defer { loading = false }
        do {
            let cur = cursors[p - 1]
            let data = try await APIClient.shared.fetchCoinTransactions(cursor: cur, limit: pageSize)
            txs = data.items
            total = data.total ?? data.items.count
            if data.hasMore, let nc = data.nextCursor, nc > 0 {
                if cursors.count == p { cursors.append(nc) } else if p < cursors.count { cursors[p] = nc }
            }
            page = p
            loaded = true
        } catch { loaded = true }
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
                            if let p {
                                pageButton(p)
                            } else {
                                Text("…").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted).frame(minWidth: 24)
                            }
                        }
                    }
                    navButton("NEXT", enabled: current < totalPages && current < maxReachable) { onChange(current + 1) }
                }
                Text("PAGE \(current) OF \(totalPages)")
                    .font(.system(size: 10, design: .monospaced)).tracking(1.2).foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28).padding(.bottom, 8)
        }
    }

    private func navButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.0)
                .foregroundStyle(enabled ? Color.ink2 : Color.muted.opacity(0.5))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(Color.paper))
                .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled).pointerCursor()
    }

    private func pageButton(_ p: Int) -> some View {
        let isCurrent = p == current
        let reachable = p <= maxReachable
        return Button(action: { if reachable && !isCurrent { onChange(p) } }) {
            Text("\(p)").font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isCurrent ? Color.paper : (reachable ? Color.ink2 : Color.muted.opacity(0.4)))
                .frame(minWidth: 32, minHeight: 32)
                .background(Capsule().fill(isCurrent ? Color.ink : Color.clear))
        }
        .buttonStyle(.plain).disabled(!reachable || isCurrent).pointerCursor()
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

// Relative-time formatter for ledger rows.
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
