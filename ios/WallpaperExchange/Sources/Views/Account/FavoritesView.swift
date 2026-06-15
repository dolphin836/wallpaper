import SwiftUI

struct FavoritesView: View {
    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs

    @State private var showAuth = false
    @State private var showEditProfile = false
    @State private var showChangePassword = false
    @State private var showCoinLedger = false
    @State private var showUpload = false

    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadError: String?
    @State private var loadGeneration = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: L10n.strings(for: prefs.language).favorites)
                Group {
                    if auth.isLoggedIn, let user = auth.user {
                        signedIn(user)
                    } else {
                        signedOut
                    }
                }
            }
            .background(Color.paper)
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .safeAreaInset(edge: .bottom) { FloatingTabBar() }
            .navigationDestination(for: WallpaperRoute.self) { route in
                WallpaperDetailView(slug: route.slug)
            }
            .sheet(isPresented: $showAuth) { AuthView() }
            .sheet(isPresented: $showEditProfile) { EditProfileSheet() }
            .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
            .sheet(isPresented: $showCoinLedger) { CoinLedgerSheet() }
            .sheet(isPresented: $showUpload) { UploadView() }
            .refreshable {
                await auth.refreshProfile()
                reload()
            }
            .task(id: auth.user?.username ?? "") {
                if auth.isLoggedIn, wallpapers.isEmpty {
                    reload()
                }
            }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: "heart.circle")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Color.muted)
            Text(L10n.strings(for: prefs.language).signInFavorites)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button {
                showAuth = true
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
                PreferencesCard()
                favoritesSection(user)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background(Color.paper)
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
                    wallpapers = []
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

    private func favoritesSection(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: L10n.strings(for: prefs.language).favorites, title: L10n.strings(for: prefs.language).favorites)
                .padding(.horizontal, 12)

            if let loadError, wallpapers.isEmpty {
                ErrorRetryView(message: loadError) { reload() }
            } else if wallpapers.isEmpty && loading {
                WallpaperGridSkeleton(count: 6)
            } else if wallpapers.isEmpty {
                EmptyStateView(
                    kicker: L10n.strings(for: prefs.language).emptyFavoritesTitle,
                    message: L10n.strings(for: prefs.language).emptyFavoritesMessage
                )
            } else {
                WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) {
                    loadNextPage(username: user.username)
                }
                if loading { LoadingFooter() }
            }
        }
    }

    private func reload() {
        loadGeneration += 1
        wallpapers = []
        cursor = nil
        hasMore = true
        loadError = nil
        if let username = auth.user?.username {
            loadNextPage(username: username)
        }
    }

    private func loadNextPage(username: String) {
        guard !loading, hasMore else { return }
        let generation = loadGeneration
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await APIClient.shared.fetchUserFavorites(username: username, cursor: cursor)
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

struct PreferencesCard: View {
    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        let s = L10n.strings(for: prefs.language)

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kicker: s.settings, title: s.settings)
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
            }
            .background(Color.paper2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.hair, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
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
