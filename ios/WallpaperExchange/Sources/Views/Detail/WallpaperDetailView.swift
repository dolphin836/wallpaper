import SwiftUI

// Immersive, action-first detail page. The wallpaper itself paints the
// whole surface (heavily blurred, dimmed), the hero floats at the
// device's wallpaper crop, and the only chrome is one mono meta line
// plus the action set: like / favorite / collect, on-device preview,
// and the coin download. Everything editorial (title, tags, uploader,
// palette, similar) lives on the web/Mac surfaces — here the wallpaper
// is the page.
struct WallpaperDetailView: View {
    let slug: String

    @Environment(AuthService.self) private var auth

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
    @State private var showLoginPrompt = false
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
                    url: detail.displayURL,
                    fallback: Color(hex: detail.dominantColor) ?? .black
                )
            }
        }
        .alert("Sign in required", isPresented: $showLoginPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Log in from the Me tab to like, favorite and download wallpapers.")
        }
    }

    private var backdropColor: Color {
        Color(hex: detail?.dominantColor) ?? .black
    }

    // The wallpaper, blown past the edges and frosted, is the page
    // surface. Dark scrim keeps the light chrome legible on any image.
    private var backdrop: some View {
        ZStack {
            backdropColor
            if let detail {
                Color.clear
                    .overlay(
                        CachedAsyncImage(url: URL(string: detail.displayURL), maxPixelDimension: 700) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            backdropColor
                        }
                    )
                    .clipped()
                    .blur(radius: 48)
                    .scaleEffect(1.25)
            }
            LinearGradient(
                colors: [.black.opacity(0.30), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func content(_ detail: WallpaperDetail) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            // Hero at the exact crop this device applies as wallpaper.
            Color.clear
                .aspectRatio(DeviceScreenRatio.value, contentMode: .fit)
                .overlay(
                    CachedAsyncImage(url: URL(string: detail.displayURL), maxPixelDimension: 1600) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(backdropColor)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
                .frame(maxHeight: 480)
                .onTapGesture { showDevicePreview = true }

            Spacer(minLength: 16)

            // One quiet technical line.
            HStack(spacing: 7) {
                Text(detail.resolutionLabel.uppercased())
                if detail.isAIGenerated == true {
                    Text("·")
                    Text("AI")
                }
                Text("·")
                Text("\(detail.width)×\(detail.height)")
                Text("·")
                Text(byteString(detail.fileSize))
            }
            .font(.mono11)
            .tracking(1.2)
            .foregroundStyle(Color.lightText.opacity(0.65))

            Spacer(minLength: 18)

            actionCluster(detail)
                .padding(.horizontal, 20)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 38)
        .environment(\.colorScheme, .dark)
    }

    // ─── actions ─────────────────────────────────────────────────

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
                    guard auth.isLoggedIn else { showLoginPrompt = true; return }
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
                        Text("Preview")
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
                guard auth.isLoggedIn else { showLoginPrompt = true; return }
                downloadState = detail.isDownloaded == true ? .downloading : .confirming
                if detail.isDownloaded == true {
                    // Already purchased — re-download is free, skip confirm.
                    startDownload(detail)
                }
            } label: {
                ctaLabel("Download · 1 coin", icon: "arrow.down.circle.fill")
            }
            .buttonStyle(.pressable)
            .confirmationDialog(
                "Download costs 1 coin",
                isPresented: confirmingBinding,
                titleVisibility: .visible
            ) {
                Button("Download · 1 coin") { startDownload(detail) }
                Button("Cancel", role: .cancel) { downloadState = .idle }
            }
        case .confirming:
            ctaLabel("Download · 1 coin", icon: "arrow.down.circle.fill")
        case .downloading:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small).tint(Color.lightText)
                Text("Saving…")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.lightText)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.accent.opacity(0.7), in: Capsule())
        case .saved:
            ctaLabel("Saved to Photos", icon: "checkmark.circle.fill")
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
        guard auth.isLoggedIn else { showLoginPrompt = true; return }
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
        guard auth.isLoggedIn else { showLoginPrompt = true; return }
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
                downloadState = .failed("Not enough coins")
            } catch {
                downloadState = .failed("Download failed")
            }
        }
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
                    CachedAsyncImage(url: URL(string: url), maxPixelDimension: 2200) { image in
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
    @State private var collections: [CollectionBrief] = []
    @State private var newTitle = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("New collection") {
                    HStack {
                        TextField("Collection name", text: $newTitle)
                        Button("Create") { createAndAdd() }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                }
                Section("My collections") {
                    if collections.isEmpty {
                        Text("No collections yet")
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
            .navigationTitle("Add to Collection")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
