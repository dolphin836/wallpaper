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
    @State private var descriptionExpanded = false

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    stagePanel(detail)
                    metadata(detail)
                    if !similar.isEmpty {
                        SectionHeader(kicker: "From the same shelf", title: "More like this")
                            .padding(.horizontal, 12)
                        WallpaperGrid(wallpapers: similar)
                    }
                }
                .padding(.bottom, 24)
            } else if let loadError {
                ErrorRetryView(message: loadError) { Task { await load() } }
            } else {
                // Skeleton mirrors the stage-panel layout.
                VStack(alignment: .leading, spacing: 16) {
                    SkeletonBlock(radius: 22)
                        .aspectRatio(0.8, contentMode: .fit)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    SkeletonBlock(radius: 5).frame(width: 180, height: 20).padding(.horizontal, 12)
                    SkeletonBlock(radius: 4).frame(width: 240, height: 12).padding(.horizontal, 12)
                }
            }
        }
        .background(Color.paper)
        // Title renders once, in the content column — a nav-bar copy
        // duplicated it right above the stage panel.
        .navigationTitle("")
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

    // The web/Mac "stage": hero image on a dominant-color tinted panel
    // with the action row inside the same card, so the wallpaper's own
    // palette frames it.
    private func stagePanel(_ detail: WallpaperDetail) -> some View {
        VStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: detail.displayURL), maxPixelDimension: 1400) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Rectangle()
                    .fill(backdropColor == .clear ? Color.paper3 : backdropColor)
                    .aspectRatio(CGFloat(max(detail.width, 1)) / CGFloat(max(detail.height, 1)), contentMode: .fit)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.hair.opacity(0.5), lineWidth: 1)
            )

            actionRow(detail)
        }
        .padding(10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.paper2)
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(
                        colors: [backdropColor.opacity(0.30), backdropColor.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.hair, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func actionRow(_ detail: WallpaperDetail) -> some View {
        HStack(spacing: 6) {
            engagementButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: likeCount,
                tint: isLiked ? .red : Color.ink2
            ) { toggleLike() }
            engagementButton(
                icon: isFavorited ? "star.fill" : "star",
                count: favoriteCount,
                tint: isFavorited ? .yellow : Color.ink2
            ) { toggleFavorite() }
            Button {
                guard auth.isLoggedIn else { showLoginPrompt = true; return }
                showAddToCollection = true
            } label: {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.paper.opacity(0.72), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            downloadButton(detail)
        }
    }

    private func engagementButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text("\(count)")
                    .font(.mono11)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.paper.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
            ctaLabel("Download · 1 coin", icon: "arrow.down.circle.fill")
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Saving…")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.lightText)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.accent.opacity(0.75), in: Capsule())
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
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.warn)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color.accentSoft, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.warn.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func ctaLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(Color.lightText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.accent, in: Capsule())
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
                    .font(.display22)
                    .foregroundStyle(Color.ink)
            }
            if let description = detail.description, !description.isEmpty {
                // AI uploads carry their full generation prompt here —
                // collapsed by default so a paragraph of prompt text
                // doesn't push the page apart.
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(descriptionExpanded ? nil : 3)
                if description.count > 140 {
                    Button(descriptionExpanded ? "Show less" : "Read more") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            descriptionExpanded.toggle()
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentInk)
                    .buttonStyle(.plain)
                }
            }

            // Technical file row — mono caps, the archive's metadata voice.
            HStack(spacing: 12) {
                stat("eye", detail.viewCount)
                stat("arrow.down.circle", detail.downloadCount)
                Text(detail.resolutionLabel.uppercased())
                    .font(.mono10)
                    .tracking(0.5)
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.paper2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                if detail.isAIGenerated == true {
                    Text("AI")
                        .font(.mono10)
                        .tracking(0.5)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentSoft, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.accent.opacity(0.4), lineWidth: 1))
                }
                Text("\(detail.width)×\(detail.height) · \(byteString(detail.fileSize))")
                    .font(.mono10)
                    .foregroundStyle(Color.muted)
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
                        Circle().fill(Color.paper3)
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
                .font(.system(size: 11))
            Text("\(count)")
                .font(.mono10)
        }
        .foregroundStyle(Color.muted)
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

// Wrapping chip rows for tags — multi-line flow, no hidden horizontal
// scroll. Same Layout algorithm as the Mac client's ChipFlow.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text("#\(item)")
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.paper2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                    .foregroundStyle(Color.ink2)
            }
        }
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                widest = max(widest, x - spacing); x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
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
