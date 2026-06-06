import SwiftUI

// Shared 'my library' grid view. Reuses MainGridTile and feeds it
// from one of four endpoints depending on `kind`.
struct MyLibraryGridView: View {
    enum Kind: String { case uploads, downloads, favorites, likes }
    let kind: Kind
    var onPick: (Wallpaper) -> Void

    @State private var auth = AuthService.shared
    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if !auth.isLoggedIn {
                    SignedOutInline(message: "Sign in to view your \(kind.rawValue).")
                } else if loading && items.isEmpty {
                    WallpaperGridSkeleton(columns: gridColumns, count: 12, spacing: 12)
                } else if let err = loadError, items.isEmpty {
                    RemoteLoadErrorView(message: err) {
                        Task { await reload() }
                    }
                } else if items.isEmpty {
                    Text("Nothing here yet.")
                        .font(.sans13).foregroundStyle(Color.muted).padding(.top, 24)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(items) { wp in
                            Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                                .onAppear { maybeLoadMore(wp) }
                        }
                    }
                    if let err = loadError {
                        HStack(spacing: 10) {
                            Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                            Button("Retry") { Task { await loadMore() } }.controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    } else if hasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
                            .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 60)
        }
        .task(id: kind.rawValue) { await reload() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false
        loadError = nil
        await loadMore()
    }
    private func loadMore() async {
        guard auth.isLoggedIn, !loading, let u = auth.user else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data: PaginatedData<Wallpaper>
            switch kind {
            case .uploads:   data = try await APIClient.shared.fetchUserUploads(username: u.username, cursor: cursor, limit: 24)
            case .downloads: data = try await APIClient.shared.fetchMyDownloads(cursor: cursor, limit: 24)
            case .favorites: data = try await APIClient.shared.fetchUserFavorites(username: u.username, cursor: cursor, limit: 24)
            case .likes:     data = try await APIClient.shared.fetchUserLikes(username: u.username, cursor: cursor, limit: 24)
            }
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }
}

// My Collections — same picker as the public Collections list, but
// only the signed-in user's own.
struct MyLibraryCollectionsView: View {
    @State private var auth = AuthService.shared
    @State private var items: [CollectionBrief] = []
    @State private var loading = false
    @State private var loadError: String?

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if !auth.isLoggedIn {
                    SignedOutInline(message: "Sign in to view your collections.")
                } else if loading && items.isEmpty {
                    WallpaperGridSkeleton(columns: gridColumns, count: 12, spacing: 12, aspectRatio: 3.0 / 2.0, cornerRadius: 12)
                } else if let err = loadError {
                    RemoteLoadErrorView(message: err) {
                        Task { await load() }
                    }
                } else if items.isEmpty {
                    Text("You haven't created any collections yet.")
                        .font(.sans13).foregroundStyle(Color.muted).padding(.top, 24)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(items) { c in
                            MyCollectionCard(brief: c)
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 60)
        }
        .task { await load() }
    }
    private func load() async {
        guard auth.isLoggedIn else { return }
        loadError = nil
        loading = true; defer { loading = false }
        do {
            let list = try await APIClient.shared.fetchMyCollections(limit: 100)
            items = list
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct MyCollectionCard: View {
    let brief: CollectionBrief
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.paper2)
                .aspectRatio(3 / 2, contentMode: .fit)
                .overlay(
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.muted)
                )
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(brief.title).font(.displayMd).foregroundStyle(Color.ink).lineLimit(1)
                Text("\(brief.wallpaperCount) WALLPAPERS")
                    .font(.kicker).tracking(1.5).foregroundStyle(Color.muted)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover ? Color.paper : Color.clear))
        .scaleEffect(hover ? 1.005 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
    }
}

// My Coins — balance hero + transactions ledger.
struct MyCoinsView: View {
    @State private var auth = AuthService.shared
    @State private var tx: [CoinTransaction] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if !auth.isLoggedIn {
                    SignedOutInline(message: "Sign in to view your coin balance.")
                } else {
                    balanceCard
                    ledgerCard
                }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 60)
            .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await reload() }
    }

    private var balanceCard: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: "Your balance", tint: Color.paper.opacity(0.6))
                Text("\(auth.user?.coins ?? 0)")
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.paper)
                    .monospacedDigit()
                Text("Earn +1 for each upload and +1 each time someone downloads yours.")
                    .font(.sans12).foregroundStyle(Color.paper.opacity(0.7))
                    .frame(maxWidth: 420, alignment: .leading)
            }
            Spacer()
            ZStack {
                Circle().fill(Color.accent)
                Circle().stroke(Color.white.opacity(0.4), lineWidth: 1)
                Text("⊙").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.ink))
    }

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kicker(text: "Transaction history")
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }

            if loading && tx.isEmpty {
                LedgerRowsSkeleton(rows: 4)
            } else if let err = loadError, tx.isEmpty {
                RemoteLoadErrorView(title: "Could not load transactions", message: err) {
                    Task { await reload() }
                }
            } else if tx.isEmpty {
                Text("No transactions yet.")
                    .font(.sans12).foregroundStyle(Color.muted)
                    .padding(20)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tx) { t in
                        ledgerRow(t).onAppear { maybeLoadMore(t) }
                    }
                }
                if let err = loadError {
                    HStack(spacing: 10) {
                        Text(err).font(.sans12).foregroundStyle(Color.ink2).lineLimit(1)
                        Button("Retry") { Task { await loadMore() } }.controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                } else if hasMore {
                    HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
                        .frame(height: 24)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func ledgerRow(_ t: CoinTransaction) -> some View {
        HStack(spacing: 14) {
            let isCredit = t.amount > 0
            ZStack {
                Circle().fill((isCredit ? Color.accent : Color.muted).opacity(0.12))
                Image(systemName: isCredit ? "arrow.down" : "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isCredit ? Color.accent : Color.muted)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.description.isEmpty ? humanize(t.txType) : t.description)
                    .font(.sans13).foregroundStyle(Color.ink).lineLimit(1)
                Text(formatDate(t.createdAt))
                    .font(.mono10).tracking(0.4).foregroundStyle(Color.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((isCredit ? "+\(t.amount)" : "\(t.amount)"))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCredit ? Color.accent : Color.ink)
                Text("Bal · \(t.balance)").font(.mono10).tracking(0.4).foregroundStyle(Color.muted)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hair.opacity(0.6)).frame(height: 0.5).padding(.horizontal, 18)
        }
    }

    private func humanize(_ tx: String) -> String {
        switch tx {
        case "upload_reward":       "Reward · upload published"
        case "download_received":   "Reward · someone downloaded yours"
        case "download_spent":      "Spent · downloaded a wallpaper"
        case "admin_grant":         "Admin grant"
        default: tx.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func formatDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return f.string(from: date)
    }

    private func reload() async {
        tx = []; cursor = nil; hasMore = false
        loadError = nil
        await loadMore()
        await auth.refreshProfile()
    }
    private func loadMore() async {
        guard auth.isLoggedIn, !loading else { return }
        loading = true; defer { loading = false }
        loadError = nil
        do {
            let data = try await APIClient.shared.fetchCoinTransactions(cursor: cursor, limit: 30)
            tx.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
    private func maybeLoadMore(_ t: CoinTransaction) {
        guard hasMore, !loading, let last = tx.last, t.id == last.id else { return }
        Task { await loadMore() }
    }
}

// Shared 'sign in' prompt for the My-Library views when the user
// isn't logged in.
struct SignedOutInline: View {
    let message: String
    @State private var auth = AuthService.shared
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.muted)
            Text(message).font(.sans12).foregroundStyle(Color.ink2)
            Button("Sign in") { auth.login() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
