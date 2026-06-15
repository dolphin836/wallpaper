import SwiftUI

// Immersive, action-first detail page. The wallpaper itself paints the
// whole surface; the only chrome is the bottom tool set: like /
// favorite / collect, on-device preview, and coin download.
struct WallpaperDetailView: View {
    let slug: String

    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs

    @State private var detail: WallpaperDetail?
    @State private var loadError: String?

    @State private var isLiked = false
    @State private var isFavorited = false
    @State private var likeCount = 0
    @State private var favoriteCount = 0

    enum DownloadState: Equatable {
        case idle
        case confirming
        case downloading
        case saved
        case failed(String)
    }
    @State private var downloadState: DownloadState = .idle
    @State private var showAddToCollection = false
    @State private var showDevicePreview = false

    var body: some View {
        ZStack {
            backdrop
            if let detail {
                content(detail)
            } else if let loadError {
                ErrorRetryView(message: loadError) { Task { await load() } }
                    .padding(.horizontal, 24)
            } else {
                skeleton
            }
        }
        .navigationTitle("")
        .inlineNavTitle()
        .showNavBarCompat()
        .transparentNavBarCompat()
        .tint(Color.lightText)
        .task(id: slug) { await load() }
        .sheet(isPresented: $showAddToCollection) {
            if let detail {
                AddToCollectionSheet(wallpaperID: detail.id)
            }
        }
        .fullScreenCoverCompat(isPresented: $showDevicePreview) {
            if let detail {
                DevicePreviewCover(
                    url: fullScreenURL(for: detail),
                    fallback: Color(hex: detail.dominantColor) ?? .black
                )
            }
        }
    }

    private var backdropColor: Color {
        Color(hex: detail?.dominantColor) ?? .black
    }

    private func fullScreenURL(for detail: WallpaperDetail) -> String {
        detail.originalURL.isEmpty ? detail.displayURL : detail.originalURL
    }

    // The wallpaper itself is the page. A subtle scrim keeps only the
    // navigation and bottom tools legible on bright images.
    private var backdrop: some View {
        ZStack {
            backdropColor
            if let detail {
                Color.clear
                    .overlay(
                        CachedAsyncImage(url: URL(string: fullScreenURL(for: detail)), maxPixelDimension: 3200) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            backdropColor
                        }
                    )
                    .clipped()
            }
            LinearGradient(
                colors: [.black.opacity(0.20), .clear, .black.opacity(0.46)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func content(_ detail: WallpaperDetail) -> some View {
        VStack(spacing: 0) {
            Spacer()
            bottomToolBar(detail)
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
        }
        .contentShape(Rectangle())
        .onTapGesture { showDevicePreview = true }
        .environment(\.colorScheme, .dark)
    }

    // ─── actions ─────────────────────────────────────────────────

    private func bottomToolBar(_ detail: WallpaperDetail) -> some View {
        HStack(spacing: 12) {
            toolButton(
                icon: isLiked ? "heart.fill" : "heart",
                tint: isLiked ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color.lightText
            ) { toggleLike() }

            toolButton(
                icon: isFavorited ? "star.fill" : "star",
                tint: isFavorited ? Color(red: 1.0, green: 0.80, blue: 0.35) : Color.lightText
            ) { toggleFavorite() }

            toolButton(icon: "rectangle.stack.badge.plus", tint: Color.lightText) {
                guard requireLogin() else { return }
                showAddToCollection = true
            }

            toolButton(icon: "iphone", tint: Color.lightText) {
                showDevicePreview = true
            }

            compactDownloadButton(detail)
        }
        .padding(10)
        .background(.black.opacity(0.30), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
    }

    private func toolButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private func compactDownloadButton(_ detail: WallpaperDetail) -> some View {
        switch downloadState {
        case .idle:
            Button {
                guard requireLogin() else { return }
                downloadState = detail.isDownloaded == true ? .downloading : .confirming
                if detail.isDownloaded == true {
                    startDownload(detail)
                }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.lightText)
                    .frame(width: 46, height: 46)
                    .background(Color.accent, in: Circle())
            }
            .buttonStyle(.pressable)
            .confirmationDialog(
                L10n.strings(for: prefs.language).downloadOneCoin,
                isPresented: confirmingBinding,
                titleVisibility: .visible
            ) {
                Button(L10n.strings(for: prefs.language).downloadOneCoin) { startDownload(detail) }
                Button(L10n.strings(for: prefs.language).cancel, role: .cancel) { downloadState = .idle }
            }
        case .confirming:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.lightText)
                .frame(width: 46, height: 46)
                .background(Color.accent.opacity(0.72), in: Circle())
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .tint(Color.lightText)
                .frame(width: 46, height: 46)
                .background(Color.accent.opacity(0.72), in: Circle())
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.lightText)
                .frame(width: 46, height: 46)
                .background(Color.accent, in: Circle())
        case .failed:
            Button {
                downloadState = .idle
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.lightText)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.pressable)
        }
    }

    private func actionCluster(_ detail: WallpaperDetail) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                engagementButton(
                    icon: isLiked ? "heart.fill" : "heart",
                    count: likeCount,
                    tint: isLiked ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color.lightText
                ) { toggleLike() }
                engagementButton(
                    icon: isFavorited ? "star.fill" : "star",
                    count: favoriteCount,
                    tint: isFavorited ? Color(red: 1.0, green: 0.80, blue: 0.35) : Color.lightText
                ) { toggleFavorite() }
                engagementButton(icon: "rectangle.stack.badge.plus", count: nil, tint: Color.lightText) {
                    guard requireLogin() else { return }
                    showAddToCollection = true
                }
            }

            HStack(spacing: 10) {
                Button {
                    showDevicePreview = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                            .font(.system(size: 14))
                        Text(L10n.strings(for: prefs.language).preview)
                            .font(.subheadline.weight(.semibold))
                    }
                    .fixedSize()
                    .foregroundStyle(Color.lightText)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 18)
                    .background(.white.opacity(0.12), in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.pressable)

                downloadButton(detail)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: downloadState)
            }
        }
    }

    private func engagementButton(icon: String, count: Int?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.10), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                if let count {
                    Text("\(count)")
                        .font(.mono10)
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.lightText.opacity(0.7))
                } else {
                    Text(" ")
                        .font(.mono10)
                }
            }
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private func downloadButton(_ detail: WallpaperDetail) -> some View {
        switch downloadState {
        case .idle:
            Button {
                guard requireLogin() else { return }
                downloadState = detail.isDownloaded == true ? .downloading : .confirming
                if detail.isDownloaded == true {
                    // Already purchased — re-download is free, skip confirm.
                    startDownload(detail)
                }
            } label: {
                ctaLabel(L10n.strings(for: prefs.language).downloadOneCoin, icon: "arrow.down.circle.fill")
            }
            .buttonStyle(.pressable)
            .confirmationDialog(
                L10n.strings(for: prefs.language).downloadOneCoin,
                isPresented: confirmingBinding,
                titleVisibility: .visible
            ) {
                Button(L10n.strings(for: prefs.language).downloadOneCoin) { startDownload(detail) }
                Button(L10n.strings(for: prefs.language).cancel, role: .cancel) { downloadState = .idle }
            }
        case .confirming:
            ctaLabel(L10n.strings(for: prefs.language).downloadOneCoin, icon: "arrow.down.circle.fill")
        case .downloading:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small).tint(Color.lightText)
                Text(L10n.strings(for: prefs.language).saving)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.lightText)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.accent.opacity(0.7), in: Capsule())
        case .saved:
            ctaLabel(L10n.strings(for: prefs.language).savedToPhotos, icon: "checkmark.circle.fill")
        case .failed(let message):
            Button {
                downloadState = .idle
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                        .lineLimit(1)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.lightText)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.14), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    private func ctaLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.lightText)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.accent, Color.accent.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            ),
            in: Capsule()
        )
        .shadow(color: Color.accent.opacity(0.45), radius: 14, y: 7)
    }

    private var skeleton: some View {
        VStack(spacing: 18) {
            SkeletonBlock(radius: 30)
                .aspectRatio(DeviceScreenRatio.value, contentMode: .fit)
                .frame(maxHeight: 480)
            SkeletonBlock(radius: 4).frame(width: 200, height: 10)
            SkeletonBlock(radius: 22).frame(height: 46).padding(.horizontal, 20)
        }
        .padding(.horizontal, 38)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(
            get: { downloadState == .confirming },
            set: { if !$0 && downloadState == .confirming { downloadState = .idle } }
        )
    }

    private func toggleLike() {
        guard requireLogin() else { return }
        guard let detail else { return }
        let wasLiked = isLiked
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isLiked.toggle()
            likeCount += isLiked ? 1 : -1
        }
        Task {
            do {
                if wasLiked {
                    try await APIClient.shared.unlike(wallpaperID: detail.id)
                } else {
                    try await APIClient.shared.like(wallpaperID: detail.id)
                }
            } catch {
                // Roll the optimistic flip back on failure.
                isLiked = wasLiked
                likeCount += wasLiked ? 1 : -1
            }
        }
    }

    private func toggleFavorite() {
        guard requireLogin() else { return }
        guard let detail else { return }
        let wasFavorited = isFavorited
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isFavorited.toggle()
            favoriteCount += isFavorited ? 1 : -1
        }
        Task {
            do {
                if wasFavorited {
                    try await APIClient.shared.unfavorite(wallpaperID: detail.id)
                } else {
                    try await APIClient.shared.favorite(wallpaperID: detail.id)
                }
            } catch {
                isFavorited = wasFavorited
                favoriteCount += wasFavorited ? 1 : -1
            }
        }
    }

    private func startDownload(_ detail: WallpaperDetail) {
        downloadState = .downloading
        Task {
            do {
                let fileURL = try await APIClient.shared.getDownloadURL(wallpaperID: detail.id)
                try await PhotoSaver.save(remoteURL: fileURL)
                downloadState = .saved
                await auth.refreshCoins()
            } catch APIError.insufficientCoins {
                downloadState = .failed(L10n.strings(for: prefs.language).notEnoughCoins)
            } catch {
                downloadState = .failed(L10n.strings(for: prefs.language).downloadFailed)
            }
        }
    }

    private func requireLogin() -> Bool {
        guard !auth.isLoggedIn else { return true }
        auth.login()
        return false
    }

    private func load() async {
        do {
            let d = try await APIClient.shared.fetchWallpaperDetail(slug: slug)
            detail = d
            isLiked = d.isLiked ?? false
            isFavorited = d.isFavorited ?? false
            likeCount = d.likeCount
            favoriteCount = d.favoriteCount
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Full-screen on-device preview: the wallpaper fills the real screen,
// lock-screen chrome on top; tap anywhere to toggle the mock.
struct DevicePreviewCover: View {
    let url: String
    let fallback: Color

    @Environment(\.dismiss) private var dismiss
    @State private var showLock = true

    var body: some View {
        ZStack {
            Color.clear
                .overlay(
                    CachedAsyncImage(url: URL(string: url), maxPixelDimension: 3200) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        fallback
                    }
                )
                .clipped()
                .ignoresSafeArea()

            if showLock {
                LockScreenOverlay(compact: false)
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.35), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, 16)
                Spacer()
                Text("TAP TO TOGGLE LOCK SCREEN")
                    .font(.kicker)
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                showLock.toggle()
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

// Pick (or create) one of the user's collections for a wallpaper.
struct AddToCollectionSheet: View {
    let wallpaperID: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(UIPrefs.self) private var prefs
    @State private var collections: [CollectionBrief] = []
    @State private var newTitle = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.strings(for: prefs.language).newCollection) {
                    HStack {
                        TextField(L10n.strings(for: prefs.language).collectionName, text: $newTitle)
                        Button(L10n.strings(for: prefs.language).create) { createAndAdd() }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                }
                Section(L10n.strings(for: prefs.language).myCollections) {
                    if collections.isEmpty {
                        Text(L10n.strings(for: prefs.language).noCollectionsYet)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(collections) { collection in
                        Button {
                            add(to: collection.id)
                        } label: {
                            HStack {
                                Text(collection.title)
                                Spacer()
                                if collection.containsWallpaper == true {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                } else {
                                    Text("\(collection.wallpaperCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(collection.containsWallpaper == true || working)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle(L10n.strings(for: prefs.language).addToCollection)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.strings(for: prefs.language).done) { dismiss() }
                }
            }
            .task {
                collections = (try? await APIClient.shared.fetchMyCollections(wallpaperID: wallpaperID)) ?? []
            }
        }
        .mediumSheetDetents()
    }

    private func add(to collectionID: Int) {
        working = true
        Task {
            defer { working = false }
            do {
                try await APIClient.shared.addToCollection(collectionID: collectionID, wallpaperID: wallpaperID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createAndAdd() {
        working = true
        Task {
            defer { working = false }
            do {
                let created = try await APIClient.shared.createCollection(title: newTitle.trimmingCharacters(in: .whitespaces))
                try await APIClient.shared.addToCollection(collectionID: created.id, wallpaperID: wallpaperID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
