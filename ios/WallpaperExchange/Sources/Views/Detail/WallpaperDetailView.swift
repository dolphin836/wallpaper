import SwiftUI

// Wallpaper detail — hero image over the dominant-color backdrop, then
// stats / palette / tags / uploader, engagement actions, the coin
// download flow (saves to Photos), and a "More like this" grid.
struct WallpaperDetailView: View {
    let slug: String

    @Environment(AuthService.self) private var auth

    @State private var detail: WallpaperDetail?
    @State private var similar: [Wallpaper] = []
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

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    hero(detail)
                    actionRow(detail)
                    metadata(detail)
                    if !similar.isEmpty {
                        Text("More like this")
                            .font(.headline)
                            .padding(.horizontal, 12)
                        WallpaperGrid(wallpapers: similar)
                    }
                }
                .padding(.bottom, 24)
            } else if let loadError {
                ErrorRetryView(message: loadError) { Task { await load() } }
            } else {
                LoadingFooter()
                    .padding(.top, 120)
            }
        }
        .background(backdropColor.opacity(0.08))
        .navigationTitle(detail?.title ?? "")
        .inlineNavTitle()
        .task(id: slug) { await load() }
        .sheet(isPresented: $showAddToCollection) {
            if let detail {
                AddToCollectionSheet(wallpaperID: detail.id)
            }
        }
        .alert("Sign in required", isPresented: $showLoginPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Log in from the Account tab to like, favorite and download wallpapers.")
        }
    }

    private var backdropColor: Color {
        Color(hex: detail?.dominantColor) ?? .clear
    }

    private func hero(_ detail: WallpaperDetail) -> some View {
        CachedAsyncImage(url: URL(string: detail.displayURL), maxPixelDimension: 1400) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(backdropColor == .clear ? Color.shimGray5 : backdropColor)
                .aspectRatio(CGFloat(max(detail.width, 1)) / CGFloat(max(detail.height, 1)), contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func actionRow(_ detail: WallpaperDetail) -> some View {
        HStack(spacing: 12) {
            engagementButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: likeCount,
                tint: isLiked ? .red : .primary
            ) { toggleLike() }
            engagementButton(
                icon: isFavorited ? "star.fill" : "star",
                count: favoriteCount,
                tint: isFavorited ? .yellow : .primary
            ) { toggleFavorite() }
            Button {
                guard auth.isLoggedIn else { showLoginPrompt = true; return }
                showAddToCollection = true
            } label: {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 17))
            }
            .buttonStyle(.bordered)

            Spacer()

            downloadButton(detail)
        }
        .padding(.horizontal, 12)
    }

    private func engagementButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.bordered)
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
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .confirmationDialog(
                "Download costs 1 coin",
                isPresented: confirmingBinding,
                titleVisibility: .visible
            ) {
                Button("Download · 1 coin") { startDownload(detail) }
                Button("Cancel", role: .cancel) { downloadState = .idle }
            }
        case .confirming:
            // confirmationDialog above drives this state; render the same
            // button so layout doesn't jump while it's up.
            Button {} label: {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        case .downloading:
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Saving…")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .saved:
            Button {} label: {
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(true)
        case .failed(let message):
            Button {
                downloadState = .idle
            } label: {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(
            get: { downloadState == .confirming },
            set: { if !$0 && downloadState == .confirming { downloadState = .idle } }
        )
    }

    private func metadata(_ detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !detail.title.isEmpty {
                Text(detail.title)
                    .font(.title3.weight(.semibold))
            }
            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                stat("eye", detail.viewCount)
                stat("arrow.down.circle", detail.downloadCount)
                Text(detail.resolutionLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.shimGray6, in: Capsule())
                Text(byteString(detail.fileSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !detail.paletteList.isEmpty {
                HStack(spacing: 6) {
                    ForEach(detail.paletteList, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .clear)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
                    }
                }
            }

            if let tags = detail.tags, !tags.isEmpty {
                FlowChips(items: tags.map(\.name))
            }

            if let uploader = detail.uploader {
                HStack(spacing: 10) {
                    CachedAsyncImage(url: URL(string: uploader.avatarURL ?? ""), maxPixelDimension: 80) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.shimGray5)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(uploader.nickname?.isEmpty == false ? uploader.nickname! : uploader.username)
                            .font(.subheadline.weight(.medium))
                        if let bio = uploader.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
    }

    private func stat(_ icon: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // ─── actions ─────────────────────────────────────────────────
    private func toggleLike() {
        guard auth.isLoggedIn else { showLoginPrompt = true; return }
        guard let detail else { return }
        let wasLiked = isLiked
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1
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
        isFavorited.toggle()
        favoriteCount += isFavorited ? 1 : -1
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
            similar = (try? await APIClient.shared.fetchSimilarWallpapers(wallpaperID: d.id, limit: 12)) ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Simple wrapping chip row for tags.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text("#\(item)")
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.shimGray6, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
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
