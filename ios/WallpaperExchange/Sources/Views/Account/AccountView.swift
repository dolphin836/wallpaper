import SwiftUI
import PhotosUI

// Account hub: signed-out it offers login/register; signed-in it shows
// the profile header, coin balance, the four library tabs (uploads /
// likes / favorites / downloads), coin ledger, and settings actions —
// the phone-sized cut of the web ProfilePage + Mac AccountView.
struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs

    @State private var showEditProfile = false
    @State private var showChangePassword = false
    @State private var showCoinLedger = false
    @State private var showUpload = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: "Me")
                Group {
                    if auth.isLoggedIn {
                        signedIn
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
            .sheet(isPresented: $showEditProfile) { EditProfileSheet() }
            .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
            .sheet(isPresented: $showCoinLedger) { CoinLedgerSheet() }
            .sheet(isPresented: $showUpload) { UploadView() }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(L10n.strings(for: prefs.language).signInFavorites)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                auth.login()
            } label: {
                Text(L10n.strings(for: prefs.language).signInRegister)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var signedIn: some View {
        if let user = auth.user {
            ScrollView {
                VStack(spacing: 16) {
                    profileHeader(user)
                    coinCard(user)
                    LibrarySection(username: user.username)
                }
                .padding(.top, 8)
            }
            .refreshable { await auth.refreshProfile() }
        } else {
            LoadingFooter()
        }
    }

    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: 8) {
            CachedAsyncImage(url: URL(string: user.avatarURL), maxPixelDimension: 200) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color.paper3)
                    .overlay(
                        Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())

            Text(user.nickname.isEmpty ? user.username : user.nickname)
                .font(.title3.weight(.semibold))
            Text("@\(user.username)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            HStack(spacing: 8) {
                profileAction("Upload", accent: true) { showUpload = true }
                profileAction("Edit Profile") { showEditProfile = true }
                profileAction("Password") { showChangePassword = true }
                profileAction("Sign Out") { auth.logout() }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func profileAction(_ title: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(accent ? Color.lightText : Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(accent ? Color.accent : Color.paper2, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(accent ? Color.clear : Color.hair, lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
    }

    private func coinCard(_ user: User) -> some View {
        Button {
            showCoinLedger = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coins")
                        .font(.script(19))
                        .foregroundStyle(.white)
                    Text("Earn 1 per upload · downloads cost 1")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
                Spacer()
                Text("\(user.coins)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                // The reference's gradient banner moment, in our warm hues.
                LinearGradient(
                    colors: [Color.accent, Color.accentInk],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: Color.accent.opacity(0.35), radius: 14, y: 7)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.pressable)
    }
}

// The four personal library tabs, each an independently paged grid.
struct LibrarySection: View {
    let username: String

    enum Tab: String, CaseIterable, Identifiable {
        case uploads = "Uploads"
        case likes = "Likes"
        case favorites = "Favorites"
        case downloads = "Downloads"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .uploads
    @State private var wallpapers: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false
    @State private var loadGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Library", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .onChange(of: tab) { _, _ in reload() }

            if wallpapers.isEmpty && loading {
                WallpaperGridSkeleton(count: 4)
            } else if wallpapers.isEmpty {
                EmptyStateView(kicker: "Nothing here yet", message: emptyMessage)
            } else {
                WallpaperGrid(wallpapers: wallpapers, hasMore: hasMore) { loadNextPage() }
                if loading { LoadingFooter() }
            }
        }
        .task { if wallpapers.isEmpty { reload() } }
    }

    private var emptyMessage: String {
        switch tab {
        case .uploads: return "Wallpapers you upload will appear here."
        case .likes: return "Wallpapers you like will appear here."
        case .favorites: return "Wallpapers you favorite will appear here."
        case .downloads: return "Wallpapers you download will appear here."
        }
    }

    private func reload() {
        loadGeneration += 1
        wallpapers = []
        cursor = nil
        hasMore = true
        loadNextPage()
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        let generation = loadGeneration
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await fetchPage()
                guard generation == loadGeneration else { return }
                wallpapers.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
            } catch {
                guard generation == loadGeneration else { return }
                hasMore = false
            }
        }
    }

    private func fetchPage() async throws -> PaginatedData<Wallpaper> {
        switch tab {
        case .uploads:
            // Owners see pending/in-review uploads too, matching the web.
            return try await APIClient.shared.fetchUserUploads(username: username, cursor: cursor, status: "0,1,5,6")
        case .likes:
            return try await APIClient.shared.fetchUserLikes(username: username, cursor: cursor)
        case .favorites:
            return try await APIClient.shared.fetchUserFavorites(username: username, cursor: cursor)
        case .downloads:
            return try await APIClient.shared.fetchUserDownloads(username: username, cursor: cursor)
        }
    }
}

// ─── sheets ──────────────────────────────────────────────────────

struct EditProfileSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var bio = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Avatar") {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Label("Choose new avatar", systemImage: "photo.circle")
                    }
                }
                Section("Profile") {
                    TextField("Nickname", text: $nickname)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Edit Profile")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
            .onAppear {
                nickname = auth.user?.nickname ?? ""
                bio = auth.user?.bio ?? ""
            }
        }
    }

    private func save() {
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do {
                if let avatarItem,
                   let data = try? await avatarItem.loadTransferable(type: Data.self) {
                    _ = try await APIClient.shared.uploadAvatar(imageData: data)
                }
                _ = try await APIClient.shared.updateProfile(nickname: nickname, bio: bio)
                await auth.refreshProfile()
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Current password", text: $oldPassword)
                SecureField("New password", text: $newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Change Password")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(newPassword.count < 6 || newPassword != confirmPassword || oldPassword.isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do {
                try await APIClient.shared.changePassword(old: oldPassword, new: newPassword)
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct CoinLedgerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var transactions: [CoinTransaction] = []
    @State private var cursor: Int?
    @State private var hasMore = true
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(transactions) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.description.isEmpty ? tx.txType : tx.description)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(tx.createdAt.prefix(10))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tx.amount > 0 ? "+\(tx.amount)" : "\(tx.amount)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(tx.amount > 0 ? .green : .red)
                    }
                }
                if hasMore {
                    LoadingFooter()
                        .onAppear { loadNextPage() }
                }
            }
            .navigationTitle("Coin History")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { if transactions.isEmpty { loadNextPage() } }
        }
    }

    private func loadNextPage() {
        guard !loading, hasMore else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let page = try await APIClient.shared.fetchCoinTransactions(cursor: cursor)
                transactions.append(contentsOf: page.items)
                cursor = page.nextCursor
                hasMore = page.hasMore
            } catch {
                hasMore = false
            }
        }
    }
}
