import SwiftUI

// Immersive, action-first detail page. The wallpaper itself paints the
// whole surface; the only chrome is the bottom tool set: like /
// favorite / collect, on-device preview, and coin download.
struct WallpaperDetailView: View {
    let slug: String
    let initialWallpaper: Wallpaper?
    let showsModalCloseButton: Bool
    let onModalClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs

    @State private var detail: WallpaperDetail?
    @State private var loadError: String?

    @State private var isLiked = false
    @State private var isFavorited = false
    @State private var likeCount = 0
    @State private var favoriteCount = 0
    @State private var downloadCount = 0
    @State private var hasDownloaded = false

    enum DownloadState: Equatable {
        case idle
        case confirming
        case downloading
        case saved
        case failed(String)
    }
    @State private var downloadState: DownloadState = .idle
    @State private var notice: DetailNotice?
    @State private var showAddToCollection = false
    @State private var showDevicePreview = false
    @State private var showInfo = false

    init(
        slug: String,
        initialWallpaper: Wallpaper? = nil,
        showsModalCloseButton: Bool = false,
        onModalClose: (() -> Void)? = nil
    ) {
        self.slug = slug
        self.initialWallpaper = initialWallpaper
        self.showsModalCloseButton = showsModalCloseButton
        self.onModalClose = onModalClose
        self._isLiked = State(initialValue: initialWallpaper?.isLiked ?? false)
        self._isFavorited = State(initialValue: initialWallpaper?.isFavorited ?? false)
        self._likeCount = State(initialValue: initialWallpaper?.likeCount ?? 0)
        self._favoriteCount = State(initialValue: initialWallpaper?.favoriteCount ?? 0)
        self._downloadCount = State(initialValue: initialWallpaper?.downloadCount ?? 0)
        self._hasDownloaded = State(initialValue: initialWallpaper?.isDownloaded ?? false)
    }

    var body: some View {
        ZStack {
            backdrop
            if let actionWallpaperID {
                content(wallpaperID: actionWallpaperID)
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
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                if showsModalCloseButton {
                    Button {
                        if let onModalClose {
                            onModalClose()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.lightText)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.30), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(L10n.strings(for: prefs.language).cancel)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if detail != nil {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.lightText)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.30), in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(L10n.strings(for: prefs.language).wallpaperInfo)
                }
            }
            #endif
        }
        .task(id: slug) { await load() }
        .sheet(isPresented: $showAddToCollection) {
            if let actionWallpaperID {
                AddToCollectionSheet(wallpaperID: actionWallpaperID)
            }
        }
        .sheet(isPresented: $showInfo) {
            if let detail {
                WallpaperInfoSheet(
                    detail: detail,
                    likeCount: likeCount,
                    favoriteCount: favoriteCount,
                    downloadCount: downloadCount
                )
            }
        }
        .fullScreenCoverCompat(isPresented: $showDevicePreview) {
            if let imageSource {
                DevicePreviewCover(
                    source: imageSource,
                    fallback: backdropColor
                )
            }
        }
    }

    private var backdropColor: Color {
        Color(hex: imageSource?.dominantColor) ?? .black
    }

    private var imageSource: DetailImageSource? {
        if let detail {
            return DetailImageSource(detail: detail)
        }
        if let initialWallpaper {
            return DetailImageSource(wallpaper: initialWallpaper)
        }
        return nil
    }

    private var actionWallpaperID: Int? {
        detail?.id ?? initialWallpaper?.id
    }

    // The wallpaper itself is the page. A subtle scrim keeps only the
    // navigation and bottom tools legible on bright images.
    private var backdrop: some View {
        ZStack {
            backdropColor
            if let imageSource {
                Color.clear
                    .overlay(
                        ProgressiveDetailImage(source: imageSource, fallback: backdropColor)
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

    private func content(wallpaperID: Int) -> some View {
        VStack(spacing: 0) {
            Spacer()

            if let notice {
                DetailNoticeBanner(notice: notice)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            bottomToolBar(wallpaperID: wallpaperID)
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
        }
        .environment(\.colorScheme, .dark)
    }

    // ─── actions ─────────────────────────────────────────────────

    private func bottomToolBar(wallpaperID: Int) -> some View {
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

            compactDownloadButton(wallpaperID: wallpaperID)
        }
        .padding(10)
        .background(.black.opacity(0.30), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
        .confirmationDialog(
            L10n.strings(for: prefs.language).downloadOneCoin,
            isPresented: confirmingBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.strings(for: prefs.language).downloadOneCoin) {
                startDownload(wallpaperID: wallpaperID)
            }
            Button(L10n.strings(for: prefs.language).cancel, role: .cancel) { downloadState = .idle }
        }
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
    private func compactDownloadButton(wallpaperID: Int) -> some View {
        switch downloadState {
        case .idle:
            Button {
                guard requireLogin() else { return }
                downloadState = hasDownloaded ? .downloading : .confirming
                if hasDownloaded {
                    startDownload(wallpaperID: wallpaperID)
                }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.lightText)
                    .frame(width: 46, height: 46)
                    .background(Color.accent, in: Circle())
            }
            .buttonStyle(.pressable)
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

                downloadButton(wallpaperID: detail.id)
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
    private func downloadButton(wallpaperID: Int) -> some View {
        switch downloadState {
        case .idle:
            Button {
                guard requireLogin() else { return }
                downloadState = hasDownloaded ? .downloading : .confirming
                if hasDownloaded {
                    // Already purchased — re-download is free, skip confirm.
                    startDownload(wallpaperID: wallpaperID)
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
                Button(L10n.strings(for: prefs.language).downloadOneCoin) {
                    startDownload(wallpaperID: wallpaperID)
                }
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

    private var confirmingBinding: Binding<Bool> {
        Binding(
            get: { downloadState == .confirming },
            set: { if !$0 && downloadState == .confirming { downloadState = .idle } }
        )
    }

    private func toggleLike() {
        guard requireLogin() else { return }
        guard let wallpaperID = actionWallpaperID else { return }
        let wasLiked = isLiked
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isLiked.toggle()
            likeCount += isLiked ? 1 : -1
        }
        Task {
            do {
                if wasLiked {
                    try await APIClient.shared.unlike(wallpaperID: wallpaperID)
                } else {
                    try await APIClient.shared.like(wallpaperID: wallpaperID)
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
        guard let wallpaperID = actionWallpaperID else { return }
        let wasFavorited = isFavorited
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isFavorited.toggle()
            favoriteCount += isFavorited ? 1 : -1
        }
        Task {
            do {
                if wasFavorited {
                    try await APIClient.shared.unfavorite(wallpaperID: wallpaperID)
                } else {
                    try await APIClient.shared.favorite(wallpaperID: wallpaperID)
                }
            } catch {
                isFavorited = wasFavorited
                favoriteCount += wasFavorited ? 1 : -1
            }
        }
    }

    private func startDownload(wallpaperID: Int) {
        let s = L10n.strings(for: prefs.language)
        let wasDownloaded = hasDownloaded
        downloadState = .downloading
        Task {
            do {
                let fileURL = try await APIClient.shared.getDownloadURL(wallpaperID: wallpaperID)
                let data = try await PhotoSaver.fetchData(remoteURL: fileURL)
                try await PhotoSaver.save(imageData: data)
                try? DownloadedWallpaperStore.save(wallpaperID: wallpaperID, data: data, sourceURL: fileURL)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    downloadState = .saved
                    if !wasDownloaded {
                        hasDownloaded = true
                        downloadCount += 1
                    }
                }
                showNotice(DetailNotice(kind: .success, title: s.savedToPhotosTitle, message: s.savedToPhotosMessage))
                await auth.refreshCoins()
            } catch APIError.insufficientCoins {
                downloadState = .failed(s.notEnoughCoins)
                showNotice(DetailNotice(kind: .error, title: s.notEnoughCoins, message: s.coinHint))
            } catch PhotoSaverError.accessDenied {
                downloadState = .failed(s.downloadFailed)
                showNotice(DetailNotice(kind: .error, title: s.downloadFailed, message: s.photoPermissionMessage))
            } catch {
                downloadState = .failed(s.downloadFailed)
                showNotice(DetailNotice(kind: .error, title: s.downloadFailed, message: s.downloadFailedMessage))
            }
        }
    }

    private func showNotice(_ nextNotice: DetailNotice) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            notice = nextNotice
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard notice == nextNotice else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                notice = nil
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
            hasDownloaded = d.isDownloaded ?? false
            likeCount = d.likeCount
            favoriteCount = d.favoriteCount
            downloadCount = d.downloadCount
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct DetailNotice: Equatable {
    enum Kind: Equatable {
        case success
        case error
    }

    let kind: Kind
    let title: String
    let message: String
}

private struct DetailNoticeBanner: View {
    let notice: DetailNotice

    private var icon: String {
        switch notice.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .success: return Color.accent
        case .error: return Color.warn
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lightText)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(Color.lightText.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct WallpaperInfoSheet: View {
    let detail: WallpaperDetail
    let likeCount: Int
    let favoriteCount: Int
    let downloadCount: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        NavigationStack {
            List {
                Section(s.wallpaperInfo) {
                    infoRow(title: s.resolution, value: "\(detail.width) x \(detail.height)", icon: "rectangle.expand.vertical")
                    infoRow(title: s.fileSizeLabel, value: fileSize, icon: "externaldrive")
                    infoRow(title: s.fileTypeLabel, value: detail.fileType.uppercased(), icon: "doc")
                    colorRow(title: s.dominantColorLabel, hex: detail.dominantColor)
                }
                Section(s.engagementStats) {
                    statRow(title: s.likeStat, value: likeCount, icon: "heart")
                    statRow(title: s.favoriteStat, value: favoriteCount, icon: "star")
                    statRow(title: s.downloadStat, value: downloadCount, icon: "arrow.down.circle")
                    statRow(title: s.viewStat, value: detail.viewCount, icon: "eye")
                }
            }
            .navigationTitle(s.wallpaperInfo)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(s.done) { dismiss() }
                }
            }
        }
        .mediumSheetDetents()
    }

    private var fileSize: String {
        guard detail.fileSize > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(detail.fileSize), countStyle: .file)
    }

    private func infoRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 11) {
            rowIcon(icon)
            Text(title)
            Spacer()
            Text(value.isEmpty ? "--" : value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func colorRow(title: String, hex: String?) -> some View {
        HStack(spacing: 11) {
            rowIcon("paintpalette")
            Text(title)
            Spacer()
            if let color = Color(hex: hex) {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
            }
            Text((hex?.isEmpty == false ? hex : nil) ?? "--")
                .foregroundStyle(.secondary)
                .font(.caption.monospaced())
        }
    }

    private func statRow(title: String, value: Int, icon: String) -> some View {
        HStack(spacing: 11) {
            rowIcon(icon)
            Text(title)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func rowIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.accentInk)
            .frame(width: 25, height: 25)
            .background(Color.accentSoft, in: Circle())
    }
}

private struct DetailImageSource: Equatable {
    let thumbURL: String
    let previewURL: String
    let originalURL: String
    let dominantColor: String?

    init(detail: WallpaperDetail) {
        thumbURL = detail.thumbURL
        previewURL = detail.previewURL
        originalURL = detail.originalURL
        dominantColor = detail.dominantColor
    }

    init(wallpaper: Wallpaper) {
        thumbURL = wallpaper.thumbURL
        previewURL = wallpaper.previewURL
        originalURL = wallpaper.originalURL
        dominantColor = wallpaper.dominantColor
    }

    var previewDisplayURL: String {
        previewURL.isEmpty ? thumbURL : previewURL
    }

    var identity: String {
        [thumbURL, previewURL, originalURL, dominantColor ?? ""].joined(separator: "|")
    }
}

private struct ProgressiveDetailImage: View {
    let source: DetailImageSource
    let fallback: Color

    @State private var lowLoaded = false
    @State private var previewLoaded = false
    @State private var originalLoaded = false
    @State private var originalFailed = false
    @State private var shouldLoadOriginal = false
    @State private var previewCanSettle = false

    private var thumbURL: URL? {
        normalizedURL(source.thumbURL)
    }

    private var previewURL: URL? {
        normalizedURL(source.previewDisplayURL)
    }

    private var originalURL: URL? {
        guard let url = normalizedURL(source.originalURL), url != previewURL else { return nil }
        return url
    }

    private var lowIsCached: Bool {
        guard let thumbURL, thumbURL != previewURL else { return false }
        return ImageCacheStore.shared.get(thumbURL, maxPixelDimension: 420) != nil
    }

    private var previewIsCached: Bool {
        guard let previewURL else { return false }
        return ImageCacheStore.shared.get(previewURL, maxPixelDimension: 1400) != nil
    }

    private var originalIsCached: Bool {
        guard let originalURL else { return false }
        return ImageCacheStore.shared.get(originalURL, maxPixelDimension: 3200) != nil
    }

    private var awaitingFirstImage: Bool {
        if previewLoaded || originalLoaded || previewCanSettle || lowIsCached || previewIsCached || originalIsCached {
            return false
        }
        return thumbURL != nil || previewURL != nil || originalURL != nil
    }

    private var awaitingOriginalImage: Bool {
        guard originalURL != nil else { return false }
        return !originalLoaded && !originalFailed && !originalIsCached
    }

    private var loadingVeilStrength: ImageLoadingVeil.Strength {
        if previewLoaded || previewIsCached || lowLoaded || lowIsCached || previewCanSettle {
            return .whisper
        }
        return .detail
    }

    var body: some View {
        ZStack {
            fallback

            if let thumbURL, thumbURL != previewURL {
                CachedAsyncImage(
                    url: thumbURL,
                    maxPixelDimension: 420,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            lowLoaded = true
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: previewLoaded || previewCanSettle ? 0 : 10)
                        .scaleEffect(previewLoaded || previewCanSettle ? 1 : 1.06)
                        .opacity(previewLoaded || originalLoaded || previewIsCached || originalIsCached ? 0 : 0.94)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if let previewURL {
                // Match WallpaperTile's 1400px decode key so detail can reuse
                // the image that was already decoded on the list page.
                CachedAsyncImage(
                    url: previewURL,
                    maxPixelDimension: 1400,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            previewLoaded = true
                            shouldLoadOriginal = originalURL != nil
                        }
                    },
                    onFailure: {
                        previewCanSettle = true
                        shouldLoadOriginal = originalURL != nil
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(originalLoaded || originalIsCached ? 0 : 1)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if let originalURL, shouldLoadOriginal || previewURL == nil || originalIsCached {
                CachedAsyncImage(
                    url: originalURL,
                    maxPixelDimension: 3200,
                    onLoad: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            originalLoaded = true
                        }
                    },
                    onFailure: {
                        originalFailed = true
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .allowsHitTesting(false)
            }

            if awaitingFirstImage || awaitingOriginalImage {
                ImageLoadingVeil(strength: loadingVeilStrength)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: source.identity) {
            lowLoaded = false
            previewLoaded = false
            originalLoaded = false
            originalFailed = false
            previewCanSettle = false
            shouldLoadOriginal = previewURL == nil || originalIsCached
            if previewURL != nil {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                shouldLoadOriginal = originalURL != nil
            }
        }
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}

// Full-screen on-device preview: the wallpaper fills the real screen,
// lock-screen chrome on top; tap anywhere to toggle the mock.
private struct DevicePreviewCover: View {
    let source: DetailImageSource
    let fallback: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(UIPrefs.self) private var prefs
    @State private var showLock = true

    var body: some View {
        ZStack {
            Color.clear
                .overlay(
                    ProgressiveDetailImage(source: source, fallback: fallback)
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
                Text(L10n.strings(for: prefs.language).tapToToggleLockScreen.uppercased())
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
