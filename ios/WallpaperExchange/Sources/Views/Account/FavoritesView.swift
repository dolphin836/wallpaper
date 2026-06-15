import SwiftUI

struct FavoritesView: View {
    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs

    @State private var showEditProfile = false
    @State private var showChangePassword = false
    @State private var showCoinLedger = false
    @State private var showUpload = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: L10n.strings(for: prefs.language).me)
                Group {
                    if auth.isLoggedIn, let user = auth.user {
                        signedIn(user)
                    } else {
                        signedOut
                    }
                }
            }
            .background(PageMesh())
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .safeAreaInset(edge: .bottom) { FloatingTabBar() }
            .navigationDestination(for: CollectionItem.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .sheet(isPresented: $showEditProfile) { EditProfileSheet() }
            .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
            .sheet(isPresented: $showCoinLedger) { CoinLedgerSheet() }
            .sheet(isPresented: $showUpload) {
                UploadView { showUpload = false }
            }
            .refreshable {
                await auth.refreshProfile()
            }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: "person.crop.circle")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Color.muted)
            Text(L10n.strings(for: prefs.language).signInFavorites)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button {
                auth.login()
            } label: {
                Text(L10n.strings(for: prefs.language).signInRegister)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lightText)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Color.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
            PreferencesCard()
                .padding(.horizontal, 12)
                .padding(.top, 14)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signedIn(_ user: User) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileCard(user)
                AccountNavigationCard(user: user) {
                    showCoinLedger = true
                }
                PreferencesCard()
            }
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(PageMesh())
    }

    private func profileCard(_ user: User) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: user.avatarURL), maxPixelDimension: 220) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.paper3)
                        .overlay(
                            Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.ink2)
                        )
                }
                .frame(width: 66, height: 66)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.nickname.isEmpty ? user.username : user.nickname)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(.caption)
                            .foregroundStyle(Color.ink2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    showCoinLedger = true
                } label: {
                    VStack(spacing: 1) {
                        Text("\(user.coins)")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentInk)
                            .contentTransition(.numericText())
                        Text(L10n.strings(for: prefs.language).coins)
                            .font(.mono10)
                            .foregroundStyle(Color.muted)
                    }
                    .frame(width: 54, height: 54)
                    .background(Color.accentSoft, in: Circle())
                    .overlay(Circle().strokeBorder(Color.accent.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.pressable)
            }

            HStack(spacing: 8) {
                profileAction(L10n.strings(for: prefs.language).upload, icon: "arrow.up.circle.fill", accent: true) {
                    showUpload = true
                }
                profileAction(L10n.strings(for: prefs.language).editProfile, icon: "person.crop.circle") {
                    showEditProfile = true
                }
                profileAction(L10n.strings(for: prefs.language).password, icon: "key") {
                    showChangePassword = true
                }
                profileAction(L10n.strings(for: prefs.language).signOut, icon: "rectangle.portrait.and.arrow.right") {
                    auth.logout()
                }
            }
        }
        .padding(14)
        .background(Color.paper2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.hair, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func profileAction(_ title: String, icon: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .foregroundStyle(accent ? Color.lightText : Color.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(accent ? Color.accent : Color.paper3, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent ? Color.clear : Color.hair, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }
}

private enum AccountWallpaperListKind: String {
    case downloads
    case favorites
    case likes

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .favorites: return "heart"
        case .likes: return "hand.thumbsup"
        }
    }

    func title(_ s: AppStrings) -> String {
        switch self {
        case .downloads: return s.myDownloads
        case .favorites: return s.favorites
        case .likes: return s.myLikes
        }
    }

    func emptyTitle(_ s: AppStrings) -> String {
        switch self {
        case .downloads: return s.emptyDownloadsTitle
        case .favorites: return s.emptyFavoritesTitle
        case .likes: return s.emptyLikesTitle
        }
    }

    func emptyMessage(_ s: AppStrings) -> String {
        switch self {
        case .downloads: return s.emptyDownloadsMessage
        case .favorites: return s.emptyFavoritesMessage
        case .likes: return s.emptyLikesMessage
        }
    }

    func fetch(username: String, cursor: Int?) async throws -> PaginatedData<Wallpaper> {
        switch self {
        case .downloads:
            return try await APIClient.shared.fetchUserDownloads(username: username, cursor: cursor)
        case .favorites:
            return try await APIClient.shared.fetchUserFavorites(username: username, cursor: cursor)
        case .likes:
            return try await APIClient.shared.fetchUserLikes(username: username, cursor: cursor)
        }
    }
}

private struct AccountNavigationCard: View {
    @Environment(UIPrefs.self) private var prefs

    let user: User
    let showCoinLedger: () -> Void

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: s.accountLibraryTitle)

            VStack(spacing: 0) {
                NavigationLink {
                    AccountWallpaperListView(kind: .downloads, username: user.username)
                } label: {
                    navRow(title: s.myDownloads, icon: "arrow.down.circle", tint: Color.blue)
                }
                .buttonStyle(.pressable)

                rowDivider

                NavigationLink {
                    AccountWallpaperListView(kind: .favorites, username: user.username)
                } label: {
                    navRow(title: s.favorites, icon: "heart", tint: Color.pink)
                }
                .buttonStyle(.pressable)

                rowDivider

                NavigationLink {
                    AccountWallpaperListView(kind: .likes, username: user.username)
                } label: {
                    navRow(title: s.myLikes, icon: "hand.thumbsup", tint: Color.green)
                }
                .buttonStyle(.pressable)

                rowDivider

                NavigationLink {
                    AccountCollectionsListView(username: user.username)
                } label: {
                    navRow(title: s.myCollections, icon: "rectangle.stack", tint: Color.orange)
                }
                .buttonStyle(.pressable)

                rowDivider

                Button(action: showCoinLedger) {
                    navRow(title: s.myCoins, icon: "creditcard", tint: Color.accent, detail: "\(user.coins)")
                }
                .buttonStyle(.pressable)
            }
            .background(Color.paper2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.hair, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 50)
    }

    private func navRow(title: String, icon: String, tint: Color, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 10)

            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.muted)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }
}

private struct AccountWallpaperListView: View {
    let kind: AccountWallpaperListKind
    let username: String

    @Environment(UIPrefs.self) private var prefs

    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?
    @State private var loadGeneration = 0

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(kicker: s.accountKicker, title: kind.title(s))
                    .padding(.horizontal, 12)

                if let loadError, wallpapers.isEmpty {
                    ErrorRetryView(message: loadError) { reload() }
                } else if wallpapers.isEmpty && loading {
                    WallpaperGridSkeleton(count: 8)
                } else if wallpapers.isEmpty {
                    EmptyStateView(kicker: kind.emptyTitle(s), message: kind.emptyMessage(s))
                } else {
                    WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore, isLoading: loading) {
                        loadNextPage()
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(PageMesh())
        .navigationTitle(kind.title(s))
        .inlineNavTitle()
        .showNavBarCompat()
        .refreshable { reload() }
        .task(id: "\(username)-\(kind.id)") {
            if wallpapers.isEmpty { reload() }
        }
    }

    private func reload() {
        loadGeneration += 1
        wallpapers = []
        cursor = nil
        hasMore = true
        loadError = nil
        loadNextPage()
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        let generation = loadGeneration
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await kind.fetch(username: username, cursor: cursor)
                guard generation == loadGeneration else { return }
                wallpapers.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
                loadError = nil
            } catch {
                guard generation == loadGeneration else { return }
                if wallpapers.isEmpty { loadError = error.localizedDescription }
                hasMore = false
            }
        }
    }
}

private struct AccountCollectionsListView: View {
    let username: String

    @Environment(UIPrefs.self) private var prefs

    @State private var collections: [CollectionItem] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?
    @State private var loadGeneration = 0

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(kicker: s.accountKicker, title: s.myCollections)
                    .padding(.horizontal, 12)

                if let loadError, collections.isEmpty {
                    ErrorRetryView(message: loadError) { reload() }
                } else if collections.isEmpty && loading {
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonBlock(radius: 14).frame(height: 160)
                        }
                    }
                    .padding(.horizontal, 12)
                } else if collections.isEmpty {
                    EmptyStateView(kicker: s.noCollectionsYet, message: s.emptyCollectionsMessage)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(collections) { collection in
                            NavigationLink(value: collection) {
                                CollectionCard(collection: collection, height: 172)
                            }
                            .buttonStyle(.pressable)
                        }

                        PagingFooter(isLoading: loading, hasMore: hasMore, showsEndState: false, onLoadMore: loadNextPage)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(PageMesh())
        .navigationTitle(s.myCollections)
        .inlineNavTitle()
        .showNavBarCompat()
        .refreshable { reload() }
        .task(id: username) {
            if collections.isEmpty { reload() }
        }
    }

    private func reload() {
        loadGeneration += 1
        collections = []
        cursor = nil
        hasMore = true
        loadError = nil
        loadNextPage()
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        let generation = loadGeneration
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await APIClient.shared.fetchUserCollections(idOrUsername: username, cursor: cursor)
                guard generation == loadGeneration else { return }
                collections.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
                loadError = nil
            } catch {
                guard generation == loadGeneration else { return }
                if collections.isEmpty { loadError = error.localizedDescription }
                hasMore = false
            }
        }
    }
}

struct PreferencesCard: View {
    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        let s = L10n.strings(for: prefs.language)

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: s.settings)
            VStack(spacing: 0) {
                preferenceRow(title: s.language, icon: "globe") {
                    Picker(s.language, selection: $prefs.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(L10n.languageName(language, strings: s)).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().padding(.leading, 38)

                preferenceRow(title: s.appearance, icon: "circle.lefthalf.filled") {
                    Picker(s.appearance, selection: $prefs.appearance) {
                        ForEach(AppearancePref.allCases) { appearance in
                            Text(L10n.appearanceName(appearance, strings: s)).tag(appearance)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().padding(.leading, 38)

                legalRow(kind: .terms, title: s.termsTitle)

                Divider().padding(.leading, 38)

                legalRow(kind: .privacy, title: s.privacyTitle)

                Divider().padding(.leading, 38)

                legalRow(kind: .dmca, title: s.dmcaTitle)

                Divider().padding(.leading, 38)

                preferenceRow(title: s.appVersion, icon: "info.circle") {
                    Text(AppVersion.display)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.muted)
                }
            }
            .background(Color.paper2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.hair, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
    }

    private func legalRow(kind: LegalDocumentKind, title: String) -> some View {
        NavigationLink {
            LegalDocumentView(kind: kind)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: kind.iconName())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentInk)
                    .frame(width: 26, height: 26)
                    .background(Color.accentSoft, in: Circle())
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func preferenceRow<Control: View>(
        title: String,
        icon: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentInk)
                .frame(width: 26, height: 26)
                .background(Color.accentSoft, in: Circle())
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ink)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        let cleanVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "1.0.0"
        let cleanBuild = build.flatMap { $0.isEmpty ? nil : $0 } ?? "1"
        return "v\(cleanVersion) (\(cleanBuild))"
    }
}
