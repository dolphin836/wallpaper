import SwiftUI
import AppKit
import AVFoundation

// Full-page wallpaper detail. Pushed onto the navigation stack from
// any wallpaper tile. Loads /wallpapers/:slug on appear to hydrate the
// richer WallpaperDetail (uploader / tags / palette) on top of the
// lighter Wallpaper carried by the list.
struct DetailPage: View {
    let slug: String
    var initialWallpaper: Wallpaper? = nil
    var onUploader: (String) -> Void
    var onWallpaper: (Wallpaper) -> Void
    // Set when presented as a modal overlay — the breadcrumb close + ESC
    // dismiss the modal instead of popping the navigation stack.
    var onClose: (() -> Void)? = nil
    var isWindowFullScreen: Bool = false

    @State private var detail: WallpaperDetail?
    @State private var similar: [Wallpaper] = []
    @State private var similarLoaded = false
    @State private var loadError: String?
    // Original decoded into the hero — from that moment the raw bytes
    // are in the image disk cache and a download completes instantly.
    // Static-image downloads stay disabled until then (videos/dynamic
    // wallpapers never load their original here, so they don't gate).
    @State private var heroOriginalLoaded = false
    @State private var mode: PreviewMode = .off
    @State private var manager = WallpaperManager.shared
    @State private var auth = AuthService.shared
    @State private var palette = PaletteEnv.shared
    @State private var isLiked: Bool = false
    @State private var isFavorited: Bool = false
    @State private var myCollections: [CollectionBrief] = []
    @State private var categories: [Category] = []
    @State private var downloadNotice: DownloadNotice?
    @State private var infoActionMessage: String?
    @State private var infoPanelHover = false
    @State private var reportingWallpaper = false
    @State private var deletingWallpaper = false
    @State private var showingDeleteConfirm = false
    @State private var showingWallpaperPicker = false
    @State private var showingCollectionPicker = false
    @State private var newCollectionTitle = ""
    @State private var creatingCollection = false
    @State private var collectionError: String?
    @FocusState private var collectionTitleFocused: Bool
    @State private var measuredActionBarWidth: CGFloat = 0
    @State private var showingFullscreenPreview = false
    @State private var selectedWallpaperSurface: WallpaperApplySurface = .desktop
    @State private var selectedDisplayTargetID = WallpaperDisplayTarget.allID
    @State private var applyingWallpaper = false
    @State private var videoDuration: Double?
    @State private var videoDurationTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(
        slug: String,
        initialWallpaper: Wallpaper? = nil,
        onUploader: @escaping (String) -> Void,
        onWallpaper: @escaping (Wallpaper) -> Void,
        onClose: (() -> Void)? = nil,
        isWindowFullScreen: Bool = false
    ) {
        self.slug = slug
        self.initialWallpaper = initialWallpaper
        self.onUploader = onUploader
        self.onWallpaper = onWallpaper
        self.onClose = onClose
        self.isWindowFullScreen = isWindowFullScreen
        _isLiked = State(initialValue: initialWallpaper?.isLiked ?? false)
        _isFavorited = State(initialValue: initialWallpaper?.isFavorited ?? false)
    }

    // Raw values are stable identifiers (ForEach ids) — display labels are
    // localized via previewModeLabel(_:).
    enum PreviewMode: String { case off = "Wallpaper", plain = "Plain", home = "Home", lock = "Lock" }

    private func previewModeLabel(_ mode: PreviewMode) -> String {
        switch mode {
        case .off: L10n.detail.previewWallpaper
        case .plain: L10n.detail.previewPlain
        case .home: L10n.detail.previewHome
        case .lock: L10n.detail.previewLock
        }
    }
    private enum DownloadNotice: Equatable {
        case success
        case set
        case insufficientCoins
        case unavailable
        case failed(String)
    }

    private struct DetailLayout {
        let size: CGSize
        let isModal: Bool
        let isFullScreen: Bool

        var isCompact: Bool { size.width < 760 }
        var isTight: Bool { size.width < 980 }

        var horizontalPadding: CGFloat {
            if isCompact { return 18 }
            if isModal { return 28 }
            return 32
        }

        var topPadding: CGFloat { isCompact ? 14 : 18 }
        var bottomPadding: CGFloat { isCompact ? 44 : 60 }
        var contentMaxWidth: CGFloat { 1280 }
        var pageWidth: CGFloat { min(size.width, contentMaxWidth) }
        var contentWidth: CGFloat { max(1, pageWidth - horizontalPadding * 2) }
        var recommendationColumns: Int {
            let spacing: CGFloat = 14
            let minimumTileWidth: CGFloat = 220
            return max(1, Int(floor((contentWidth + spacing) / (minimumTileWidth + spacing))))
        }
        var recommendationLimit: Int { recommendationColumns * 2 }
        var stagePadding: CGFloat { isCompact ? 14 : 20 }
        var stageSpacing: CGFloat { isCompact ? 14 : 16 }
        var actionPadding: CGFloat { isCompact ? 12 : 14 }
        var metaPadding: CGFloat { isCompact ? 16 : 20 }
        var heroViewportHeight: CGFloat { max(size.height, isCompact ? 520 : 600) }
        var overlayHorizontalPadding: CGFloat { isCompact ? 16 : 28 }
        var overlayBottomPadding: CGFloat {
            if isFullScreen {
                return isCompact ? 72 : 92
            }
            return isCompact ? 36 : 44
        }
        var topControlsHorizontalPadding: CGFloat { isCompact ? 22 : 46 }
        var topControlsTopPadding: CGFloat { isCompact ? 22 : 30 }
        var toolbarMaxWidth: CGFloat {
            let preferred: CGFloat = isCompact ? 620 : 900
            return max(320, min(preferred, size.width - overlayHorizontalPadding * 2))
        }
        var actionBarAvailableWidth: CGFloat { max(320, size.width - overlayHorizontalPadding * 2) }

        var heroMaxHeight: CGFloat {
            let h = max(size.height, 560)
            let proportional = h * (isModal ? 0.56 : 0.62)
            let cap: CGFloat = isCompact ? 500 : 680
            return min(max(proportional, 300), cap)
        }
    }

    private var deviceMode: DeviceMockup.Mode {
        switch mode {
        case .home: .home
        case .lock: .lock
        default: .plain
        }
    }

    private var detailRequestKey: String {
        let primary = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { return primary }
        if let fallbackSlug = initialWallpaper?.slug.trimmingCharacters(in: .whitespacesAndNewlines), !fallbackSlug.isEmpty {
            return fallbackSlug
        }
        if let fallbackID = initialWallpaper?.id, fallbackID > 0 {
            return String(fallbackID)
        }
        return primary
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = DetailLayout(size: proxy.size, isModal: onClose != nil, isFullScreen: isWindowFullScreen)
            ZStack(alignment: .top) {
                detailAmbientBackground(size: proxy.size)
                    .ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        immersivePage(layout: layout)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .id(detailRequestKey)
                .frame(width: proxy.size.width, height: proxy.size.height)

                detailTopControls(detail: detail, layout: layout)
                    .padding(.horizontal, layout.topControlsHorizontalPadding)
                    .padding(.top, layout.topControlsTopPadding)
                    .zIndex(20)

                if showingFullscreenPreview, let detail, !isVideo(detail: detail) {
                    FullscreenWallpaperPreview(
                        lowURL: detailPreviewPosterURL(detail),
                        highURL: detailHeroImageURL(detail),
                        resolutionName: fullscreenResolutionName(detail),
                        dimensions: "\(detail.width.formatted()) × \(detail.height.formatted())",
                        onClose: { showingFullscreenPreview = false }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .animation(.easeOut(duration: 0.18), value: showingFullscreenPreview)
            .task(id: "\(slug)-\(detail?.id ?? 0)-\(layout.recommendationLimit)") {
                await loadSimilar(limit: layout.recommendationLimit)
            }
        }
        .task(id: detailRequestKey) { await load() }
        .onPreferenceChange(ActionBarWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            measuredActionBarWidth = width
        }
        .confirmationDialog(
            L10n.detail.deleteConfirmTitle,
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.detail.deleteWallpaper, role: .destructive) {
                if let detail {
                    Task { await deleteWallpaper(detail) }
                }
            }
            Button(L10n.common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.detail.deleteConfirmMessage)
        }
    }

    private func immersivePage(layout: DetailLayout) -> some View {
        VStack(spacing: 0) {
            immersiveHero(layout: layout)
            if shouldShowRecommendationSkeleton {
                recommendationsSkeletonBand(layout: layout)
            } else if let d = detail, !similar.isEmpty {
                recommendationsBand(detail: d, layout: layout)
            }
        }
    }

    private var shouldShowRecommendationSkeleton: Bool {
        if detail == nil {
            return loadError == nil
        }
        return !similarLoaded
    }

    private func detailAmbientBackground(size: CGSize) -> some View {
        let colors = ambientColors()
        let c1 = colors.indices.contains(0) ? colors[0] : Color.brandPaletteC1
        let c2 = colors.indices.contains(1) ? colors[1] : c1
        let c3 = colors.indices.contains(2) ? colors[2] : c2
        let r = max(size.width, size.height)

        return ZStack {
            LinearGradient(
                colors: [
                    Color.paper.blended(with: c1, fraction: 0.36),
                    Color.paper.blended(with: c2, fraction: 0.24),
                    Color.paper.blended(with: c3, fraction: 0.32),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                RadialGradient(colors: [c1.opacity(0.72), .clear],
                               center: UnitPoint(x: 0.18, y: 0.22),
                               startRadius: 0,
                               endRadius: r * 0.50)
                RadialGradient(colors: [c2.opacity(0.56), .clear],
                               center: UnitPoint(x: 0.88, y: 0.16),
                               startRadius: 0,
                               endRadius: r * 0.52)
                RadialGradient(colors: [c3.opacity(0.62), .clear],
                               center: UnitPoint(x: 0.42, y: 0.86),
                               startRadius: 0,
                               endRadius: r * 0.58)
            }
            .blur(radius: 74)
            .saturation(1.28)
            .opacity(0.64)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.20),
                    Color.paper.opacity(0.08),
                    Color.black.opacity(0.10),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.42), value: palette.c1)
        .animation(.easeOut(duration: 0.42), value: palette.c2)
        .animation(.easeOut(duration: 0.42), value: palette.c3)
        .animation(.easeOut(duration: 0.42), value: palette.isDefault)
    }

    private func ambientColors() -> [Color] {
        if !palette.isDefault {
            return [palette.c1, palette.c2, palette.c3]
        }
        let hexes = ambientHexes()
        return hexes.map { Color(hex: $0) }
    }

    private func ambientHexes() -> [String] {
        if let detail {
            let palette = detail.paletteList
            if palette.count >= 3 {
                return [palette[palette.count - 2], palette[1], palette[palette.count - 1]]
            }
            if let dominant = detail.dominantColor, !dominant.isEmpty {
                return [dominant, dominant, dominant]
            }
        }

        if let wallpaper = initialWallpaper {
            let palette = wallpaperPaletteList(wallpaper)
            if palette.count >= 3 {
                return [palette[palette.count - 2], palette[1], palette[palette.count - 1]]
            }
            if let dominant = wallpaper.dominantColor, !dominant.isEmpty {
                return [dominant, dominant, dominant]
            }
        }

        return ["#E9B982", "#DFA089", "#F0CA90"]
    }

    private func wallpaperPaletteList(_ wallpaper: Wallpaper) -> [String] {
        (wallpaper.colorPalette ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func immersiveHero(layout: DetailLayout) -> some View {
        ZStack {
            immersiveHeroMedia(layout: layout)
            heroVignette
        }
        .frame(width: layout.size.width, height: layout.heroViewportHeight)
        .overlay(alignment: .bottom) {
            if detail != nil, isShowingDetailActionPopup {
                actionPopupDismissLayer(layout: layout)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .overlay {
            if let loadError, detail == nil {
                RemoteLoadErrorView(message: loadError) {
                    Task { await load() }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .frame(width: layout.pageWidth, alignment: .center)
                .zIndex(30)
            }
        }
        .overlay(alignment: .bottom) {
            detailActionOverlay(detail: detail, layout: layout)
                .zIndex(40)
        }
        .clipped()
    }

    @ViewBuilder
    private func immersiveHeroMedia(layout: DetailLayout) -> some View {
        if let d = detail, let videoURL = livePreviewVideoURL(detail: d) {
            fittedHeroMedia(
                sourceSize: detailHeroSourceSize(d),
                layout: layout,
                background: .black
            ) {
                LiveVideoPreview(
                    sourceURL: videoURL,
                    posterURL: detailPreviewPosterURL(d),
                    dominantColor: d.dominantColor ?? initialWallpaper?.dominantColor
                )
            }
        } else if let d = detail {
            let frames = dynamicFrameURLs(detail: d)
            if frames.count > 1 {
                fittedHeroMedia(
                    sourceSize: detailHeroSourceSize(d),
                    layout: layout,
                    background: Color(hex: d.dominantColor ?? initialWallpaper?.dominantColor ?? "#111111")
                ) {
                    DynamicFramePreview(
                        frameURLs: frames,
                        posterURL: detailPreviewPosterURL(d),
                        dominantColor: d.dominantColor ?? initialWallpaper?.dominantColor
                    )
                }
            } else {
                progressivePosterImage(detail: d, layout: layout)
            }
        } else if let wallpaper = initialWallpaper {
            fittedHeroMedia(
                sourceSize: CGSize(width: wallpaper.width, height: wallpaper.height),
                layout: layout,
                background: Color(hex: wallpaper.dominantColor ?? "#111111")
            ) {
                posterImage(
                    url: URL(string: wallpaper.displayURL),
                    dominantColor: wallpaper.dominantColor,
                    maxPixelDimension: 1100
                )
            }
        } else {
            LinearGradient(
                colors: [Color.black, Color.paper2.blended(with: Color.black, fraction: 0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    private func posterImage(url: URL?, dominantColor: String?, maxPixelDimension: Int) -> some View {
        CachedAsyncImage(url: url, maxPixelDimension: maxPixelDimension) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color(hex: dominantColor ?? "#111111")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func progressivePosterImage(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        fittedHeroMedia(
            sourceSize: detailHeroSourceSize(d),
            layout: layout,
            background: Color(hex: d.dominantColor ?? initialWallpaper?.dominantColor ?? "#111111")
        ) {
            ZStack {
                if let wallpaper = initialWallpaper {
                    posterImage(
                        url: URL(string: wallpaper.displayURL),
                        dominantColor: wallpaper.dominantColor,
                        maxPixelDimension: 1100
                    )
                }

                CachedAsyncImage(
                    url: detailHeroImageURL(d),
                    maxPixelDimension: detailHeroDecodeDimension(detail: d, layout: layout),
                    onLoad: { heroOriginalLoaded = true }
                ) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
    }

    // The regular Mac feeds intentionally include every wallpaper. Keep the
    // immersive cover treatment only when the displayed asset can fill the
    // live hero without enlargement; smaller media stays at native size (or
    // shrinks to fit) and is centred over its dominant-colour backdrop.
    private func fittedHeroMedia<Content: View>(
        sourceSize: CGSize,
        layout: DetailLayout,
        background: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let canvasSize = detailHeroCanvasSize(sourceSize: sourceSize, layout: layout)
        return ZStack {
            background
            content()
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
        }
        .frame(width: layout.size.width, height: layout.heroViewportHeight)
        .clipped()
    }

    private func detailHeroCanvasSize(sourceSize: CGSize, layout: DetailLayout) -> CGSize {
        let viewport = CGSize(width: max(1, layout.size.width), height: max(1, layout.heroViewportHeight))
        guard sourceSize.width > 0, sourceSize.height > 0 else { return viewport }

        if sourceSize.width >= viewport.width.rounded(.up),
           sourceSize.height >= viewport.height.rounded(.up) {
            return viewport
        }

        let scale = min(1, viewport.width / sourceSize.width, viewport.height / sourceSize.height)
        return CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )
    }

    private func detailHeroSourceSize(_ d: WallpaperDetail) -> CGSize {
        guard d.width > 0, d.height > 0 else { return .zero }
        let width = CGFloat(d.width)
        let height = CGFloat(d.height)
        let scale: CGFloat

        if livePreviewVideoURL(detail: d) != nil {
            // The backend's detail preview is capped at 480 px high.
            scale = min(1, 480 / height)
        } else if d.isDynamic {
            // Dynamic HEIC frames are exported at no more than 1600 px wide.
            scale = min(1, 1600 / width)
        } else {
            scale = 1
        }

        return CGSize(width: width * scale, height: height * scale)
    }

    // Static images gate on the hero's original being decoded (instant
    // cache-hit download afterwards); videos and dynamic wallpapers
    // download separately and stay available immediately.
    private func downloadReady(_ d: WallpaperDetail) -> Bool {
        isVideo(detail: d) || d.isDynamic || heroOriginalLoaded
    }

    private var heroVignette: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.36), Color.clear, Color.black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.38)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private func immersiveActionBar(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        ViewThatFits(in: .horizontal) {
            immersiveToolbar(detail: d, layout: layout, compact: false)
            immersiveToolbar(detail: d, layout: layout, compact: true)
        }
        .frame(maxWidth: layout.toolbarMaxWidth)
        .animation(.easeOut(duration: 0.16), value: showingWallpaperPicker)
    }

    private func immersiveToolbar(detail d: WallpaperDetail, layout: DetailLayout, compact: Bool) -> some View {
        let downloading = manager.downloading.contains(d.id)
        let downloaded = isLocalDownloaded(d)
        return HStack(spacing: compact ? 8 : 12) {
            toolbarIconButton(systemName: "chevron.left", help: L10n.shell.back) {
                closeOrDismiss()
            }
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle(d.title))
                    .font(.system(size: compact ? 14 : 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(metaSpecText(detail: d))
                    .font(.mono10)
                    .tracking(0.35)
                    .foregroundStyle(Color.white.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: compact ? 170 : 260, alignment: .leading)

            if !compact {
                toolbarIconButton(systemName: downloaded ? "checkmark.circle" : "arrow.down.to.line", help: downloadButtonText(detail: d, downloaded: downloaded, downloading: downloading)) {
                    Task { await downloadOriginal(d) }
                }
                .disabled(downloading || downloaded || !downloadReady(d))
            }

            toolbarIconButton(systemName: "square.and.arrow.up", help: "Share") {
                shareWallpaper(d)
            }

            addToListToolbarMenu(d)

            toolbarIconButton(
                systemName: isFavorited ? "heart.fill" : "heart",
                help: isFavorited ? L10n.detail.saved : L10n.detail.favorite,
                active: isFavorited,
                activeColor: Color.stateLike
            ) {
                Task { await toggleFavorite(d) }
            }

            Button(action: {
                withAnimation(.easeOut(duration: 0.16)) {
                    showingWallpaperPicker.toggle()
                }
            }) {
                HStack(spacing: 7) {
                    if applyingWallpaper || downloading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.ink)
                            .scaleEffect(0.72)
                            .frame(width: 12, height: 12)
                    }
                    Text(downloadAndSetButtonText(detail: d, downloaded: downloaded))
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, compact ? 15 : 22)
                .frame(height: 38)
                .background(Capsule().fill(Color.white.opacity(0.96)))
                .opacity(downloadReady(d) ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .disabled(downloading || applyingWallpaper || !downloadReady(d))
            .keyboardShortcut("d", modifiers: .command)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassSurface(Capsule(), tone: .dark, lighting: 0.75)
    }

    // GlassKit icon button inside the dark toolbar. The custom hover
    // tip is disabled (the bar hugs the window's bottom edge, a tip
    // below would clip) — the native help tooltip covers it.
    private func toolbarIconButton(
        systemName: String,
        help: String,
        active: Bool = false,
        activeColor: Color = Color.accent,
        action: @escaping () -> Void
    ) -> some View {
        GlassIconButton(
            icon: systemName,
            tone: .dark,
            size: 38,
            iconSize: 16,
            active: active,
            activeColor: activeColor,
            showTip: false,
            action: action
        )
        .help(help)
    }

    private func detailTopControls(detail d: WallpaperDetail?, layout: DetailLayout) -> some View {
        HStack(alignment: .top, spacing: 12) {
            detailTopButton(systemName: "chevron.left", help: L10n.shell.back) {
                closeOrDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer(minLength: 0)

            if let d {
                detailInfoHoverButton(detail: d)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Floating circles over the hero (back / info) share the exact same
    // GlassKit geometry and dark-glass interaction states.
    private func detailTopButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        GlassCircleButton(
            icon: systemName,
            help: help,
            tone: .dark,
            size: 38,
            iconSize: 15,
            action: action
        )
    }

    private func detailInfoHoverButton(detail d: WallpaperDetail) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            detailTopButton(systemName: "info.circle", help: L10n.detail.info) {
                withAnimation(.easeOut(duration: 0.16)) {
                    infoPanelHover = true
                }
            }

            if infoPanelHover {
                detailInfoPanel(detail: d)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                infoPanelHover = hovering
            }
        }
    }

    private func detailInfoPanel(detail d: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            infoPanelRow(icon: "person.crop.circle", label: L10n.detail.uploadedBy, value: uploaderName(d))
            infoPanelRow(icon: "folder", label: L10n.detail.category, value: categoryName(for: d))
            infoColorRow(detail: d)

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)

            HStack(spacing: 8) {
                infoStat(icon: "arrow.down.circle", value: "\(d.downloadCount)", label: L10n.detail.statDownloads)
                infoStat(icon: "heart", value: "\(d.likeCount)", label: L10n.detail.statLikes)
                infoStat(icon: "star", value: "\(d.favoriteCount)", label: L10n.detail.statFavorited)
            }

            HStack(spacing: 8) {
                if isOwner(d) {
                    weakInfoAction(icon: "trash", title: L10n.detail.deleteWallpaper, destructive: true) {
                        showingDeleteConfirm = true
                    }
                    .disabled(deletingWallpaper)
                } else {
                    weakInfoAction(icon: "flag", title: reportingWallpaper ? L10n.detail.reporting : L10n.detail.report, destructive: false) {
                        Task { await reportWallpaper(d) }
                    }
                    .disabled(reportingWallpaper)
                }
                Spacer(minLength: 0)
                if let infoActionMessage {
                    Text(infoActionMessage)
                        .font(.mono10)
                        .tracking(0.4)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(width: 306, alignment: .leading)
        .glassPanel(cornerRadius: 18)
    }

    private func infoPanelRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.54))
                .frame(width: 14)
            Text(label)
                .font(.mono10)
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.50))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func infoColorRow(detail d: WallpaperDetail) -> some View {
        let hex = (d.dominantColor ?? "#888888").uppercased()
        return HStack(alignment: .center, spacing: 9) {
            Image(systemName: "paintpalette")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.54))
                .frame(width: 14)
            Text(L10n.detail.color)
                .font(.mono10)
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.50))
                .frame(width: 72, alignment: .leading)
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: hex))
                    .frame(width: 18, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.34), lineWidth: 1))
                Text(hex)
                    .font(.mono10)
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.86))
            }
        }
    }

    private func infoStat(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(value)
                    .font(.mono10)
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.white.opacity(0.82))
        .help(label)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func weakInfoAction(icon: String, title: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(destructive ? Color.red.opacity(0.78) : Color.white.opacity(0.62))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func uploaderName(_ detail: WallpaperDetail) -> String {
        guard let uploader = detail.uploader else { return L10n.detail.unknownUploader }
        if let nickname = uploader.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            return "\(nickname) · @\(uploader.username)"
        }
        return "@\(uploader.username)"
    }

    private func categoryName(for detail: WallpaperDetail) -> String {
        guard let id = detail.categoryID else { return "—" }
        return categories.first { $0.id == id }?.name ?? "#\(id)"
    }

    private func addToListToolbarMenu(_ detail: WallpaperDetail) -> some View {
        Button {
            toggleCollectionPicker(detail)
        } label: {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(L10n.detail.addToList)
    }

    private func recommendationsBand(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        moreLikeThis(layout: layout, dark: false)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.isCompact ? 34 : 46)
            .padding(.bottom, layout.bottomPadding)
            .frame(width: layout.pageWidth, alignment: .leading)
            .frame(width: layout.size.width, alignment: .center)
            .background(recommendationsBackground(dominantColor: d.dominantColor))
    }

    private func recommendationsSkeletonBand(layout: DetailLayout) -> some View {
        recommendationsSkeleton(layout: layout)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.isCompact ? 34 : 46)
            .padding(.bottom, layout.bottomPadding)
            .frame(width: layout.pageWidth, alignment: .leading)
            .frame(width: layout.size.width, alignment: .center)
            .background(recommendationsBackground(dominantColor: detail?.dominantColor ?? initialWallpaper?.dominantColor))
    }

    private func recommendationsSkeleton(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonLine(width: 72, height: 9)
                    SkeletonLine(width: 220, height: 32, cornerRadius: 10)
                }
                Spacer()
                SkeletonLine(width: 72, height: 10)
            }
            Rectangle().fill(Color.hair).frame(height: 1)
            WallpaperGridSkeleton(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                    count: layout.recommendationColumns
                ),
                count: max(layout.recommendationLimit, layout.recommendationColumns),
                spacing: 14,
                aspectRatio: 3.0 / 2.0,
                cornerRadius: 10
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func recommendationsBackground(dominantColor: String?) -> some View {
        let tint = Color(hex: dominantColor ?? "#888888")
        return ZStack {
            LinearGradient(
                colors: [
                    Color.paper.opacity(0.04),
                    tint.opacity(0.08),
                    Color.paper.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [tint.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )
        }
    }

    private func detailHeroImageURL(_ d: WallpaperDetail) -> URL? {
        if !isVideo(detail: d), !d.isDynamic {
            let originalURL = d.originalURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !originalURL.isEmpty {
                return URL(string: originalURL)
            }
        }
        return detailPreviewPosterURL(d)
    }

    private func dynamicFrameURLs(detail d: WallpaperDetail) -> [URL] {
        guard d.isDynamic, !isVideo(detail: d), let raw = d.frameURLs else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
    }

    private func detailPreviewPosterURL(_ d: WallpaperDetail) -> URL? {
        let detailURL = d.displayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detailURL.isEmpty {
            return URL(string: detailURL)
        }
        return initialWallpaper.flatMap { URL(string: $0.displayURL) }
    }

    private func detailHeroDecodeDimension(detail d: WallpaperDetail, layout: DetailLayout) -> Int {
        let sourceMax = CGFloat(max(d.width, d.height, 1))
        let screenScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? NSScreen.main?.backingScaleFactor ?? 2
        let viewportMax = max(layout.size.width, layout.heroViewportHeight) * screenScale
        let target = min(max(viewportMax, 2600), sourceMax, 5200)
        return max(1, Int(target.rounded(.up)))
    }

    private func displayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.detail.wallpaperTitle : trimmed
    }

    private func shareWallpaper(_ detail: WallpaperDetail) {
        let key = detail.slug.isEmpty ? "\(detail.id)" : detail.slug
        if let url = URL(string: "https://wallpaperexchange.com/wallpaper/\(key)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func closeOrDismiss() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func detailSkeleton(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.isCompact ? 18 : 24) {
            VStack(spacing: layout.stageSpacing) {
                SkeletonPlate(aspectRatio: 16.0 / 9.0, cornerRadius: 18)
                    .frame(maxHeight: layout.heroMaxHeight)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        SkeletonLine(width: 160, height: 16)
                        SkeletonLine(width: 220, height: 11)
                        Spacer(minLength: 0)
                    }
                    Rectangle().fill(Color.hair).frame(height: 1)
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonLine(width: 96, height: 30, cornerRadius: 15)
                        }
                        Spacer(minLength: 0)
                        SkeletonLine(width: 160, height: 34, cornerRadius: 17)
                    }
                }
                .padding(layout.actionPadding)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.paper.opacity(0.82)))
            }
            .padding(layout.stagePadding)
            .background(
                ZStack {
                    Color.paper
                    LinearGradient(colors: [Color.paper2.opacity(0.8), Color.paper.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonLine(width: 86, height: 8)
                            SkeletonLine(width: 42, height: 24)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            SkeletonLine(width: 112, height: 9)
                            SkeletonLine(width: 180, height: 24)
                            SkeletonLine(width: 220, height: 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(layout.metaPadding)
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.paper))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hair, lineWidth: 1))
        }
    }

    // Full-bleed blurred preview of the wallpaper itself behind the
    // whole panel (web .wd-backdrop: blur 38 / saturate 1.4 / scale 1.18)
    // with a soft paper scrim on top so content stays legible.
    private func backdrop(size: CGSize) -> some View {
        ZStack {
            Color.paper
            if let d = detail, let url = URL(string: d.displayURL) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 38).saturation(1.4).scaleEffect(1.18)
                } placeholder: {
                    Color(hex: d.dominantColor ?? "#bbb").opacity(0.4)
                }
                .clipped()
            }
            LinearGradient(colors: [Color.paper.opacity(0.42), Color.paper.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func breadcrumb(detail: WallpaperDetail) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Kicker(text: L10n.detail.specimen(detail.id))
            Spacer()
        }
    }

    // Stage panel — a dominant-color gradient card holding the hero +
    // the toolbar (web .wd-panel).
    private func stagePanel(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        let tint = Color(hex: d.dominantColor ?? "#888")
        return VStack(spacing: layout.stageSpacing) {
            hero(detail: d, layout: layout)
            downloadNoticeView(detail: d, layout: layout)
            if showingCollectionPicker {
                collectionPicker(detail: d, layout: layout)
            }
            if showingWallpaperPicker {
                wallpaperPicker(detail: d, layout: layout)
            }
            actionBar(detail: d, wallpaper: initialWallpaper, layout: layout)
        }
        .padding(layout.stagePadding)
        .background(
            ZStack {
                Color.paper
                LinearGradient(colors: [tint.opacity(0.22), Color.paper.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [tint.opacity(0.5), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
                RadialGradient(colors: [tint.opacity(0.4), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 40, x: 0, y: 22)
    }

    private func hero(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        Group {
            if let videoURL = livePreviewVideoURL(detail: detail) {
                liveVideoHero(detail: detail, layout: layout, sourceURL: videoURL)
            } else if mode == .off {
                rawHeroImage(detail: detail, layout: layout)
            } else {
                // Plain / Home / Lock → draw the actual device (monitor
                // bezel + stand) with the wallpaper on screen.
                DeviceMockup(wallpaper: lightWallpaper(detail), controlledMode: deviceMode, showChrome: false)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: layout.heroMaxHeight)
                    .overlay(alignment: .topLeading) {
                        previewChips(detail: detail)
                            .padding(14)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func livePreviewVideoURL(detail d: WallpaperDetail) -> URL? {
        guard isVideo(detail: d),
              let value = d.previewVideoURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    @ViewBuilder
    private func downloadNoticeView(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        if let downloadNotice {
            let tone = noticeTone(downloadNotice)
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(tone.ink.opacity(0.13))
                    Image(systemName: noticeIcon(downloadNotice))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone.ink)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(noticeTitle(downloadNotice))
                        .font(.mono10)
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(tone.ink)
                    Text(noticeMessage(downloadNotice, detail: d))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(tone.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if downloadNotice == .insufficientCoins {
                    Button(action: openUploadOnWeb) {
                        Text(L10n.detail.uploadToEarn)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(tone.ink))
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { self.downloadNotice = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tone.ink.opacity(0.74))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: resolvedActionBarWidth(layout: layout), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tone.background))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tone.border, lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func noticeTone(_ notice: DownloadNotice) -> (background: Color, border: Color, ink: Color, text: Color) {
        switch notice {
        case .success, .set:
            let ink = Color(hex: "#2f6b3e")
            return (Color(hex: "#edf8ef"), ink.opacity(0.65), ink, Color(hex: "#1f4827"))
        case .insufficientCoins:
            let ink = Color(hex: "#9a6a18")
            return (Color(hex: "#fbf2dd"), Color(hex: "#b07a1a").opacity(0.72), ink, Color(hex: "#5e3f08"))
        case .unavailable, .failed:
            return (Color.warn.opacity(0.10), Color.warn.opacity(0.36), Color.warn, Color.ink2)
        }
    }

    private func noticeIcon(_ notice: DownloadNotice) -> String {
        switch notice {
        case .success: "checkmark"
        case .set: "display"
        case .insufficientCoins: "creditcard"
        case .unavailable: "hammer"
        case .failed: "exclamationmark"
        }
    }

    private func noticeTitle(_ notice: DownloadNotice) -> String {
        switch notice {
        case .success: L10n.detail.noticeDownloadedTitle
        case .set: L10n.detail.noticeSetTitle
        case .insufficientCoins: L10n.detail.noticeInsufficientCoinsTitle
        case .unavailable: L10n.detail.noticeUnavailableTitle
        case .failed: L10n.detail.noticeFailedTitle
        }
    }

    private func noticeMessage(_ notice: DownloadNotice, detail d: WallpaperDetail) -> String {
        switch notice {
        case .success:
            return L10n.detail.noticeSuccessMessage("wallpaper_\(String(format: "%03d", d.id))", byteString(d.fileSize))
        case .set:
            return L10n.detail.noticeSetMessage
        case .insufficientCoins:
            return L10n.detail.noticeInsufficientCoinsMessage(auth.user?.coins ?? 0)
        case .unavailable:
            return L10n.detail.noticeUnavailableMessage
        case .failed(let message):
            return message
        }
    }

    private func openUploadOnWeb() {
        if let url = URL(string: "https://wallpaperexchange.com/upload") {
            NSWorkspace.shared.open(url)
        }
    }

    // Raw wallpaper mirrors web .wd-hero-img: the image gets max-width /
    // max-height constraints, then the rounded border is attached to the
    // actual rendered image rect rather than a full-width SwiftUI frame.
    private func rawHeroImage(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        let size = rawHeroSize(detail: detail, layout: layout)
        return HStack {
            Spacer(minLength: 0)
            CachedAsyncImage(url: detailHeroImageURL(detail), maxPixelDimension: detailHeroDecodeDimension(detail: detail, layout: layout)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color(hex: detail.dominantColor ?? "#bbb")
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                previewChips(detail: detail)
                    .padding(10)
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
    }

    private func liveVideoHero(detail: WallpaperDetail, layout: DetailLayout, sourceURL: URL) -> some View {
        let size = rawHeroSize(detail: detail, layout: layout)
        return HStack {
            Spacer(minLength: 0)
            LiveVideoPreview(
                sourceURL: sourceURL,
                posterURL: detailPreviewPosterURL(detail),
                dominantColor: detail.dominantColor
            )
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                previewChips(detail: detail)
                    .padding(10)
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
    }

    private func previewChips(detail d: WallpaperDetail) -> some View {
        HStack(alignment: .top, spacing: 4) {
            previewChip(d.resolutionLabel, icon: nil, variant: .regular)
            if isLive(detail: d) {
                previewChip(L10n.detail.chipLive, icon: "play.fill", variant: .regular)
            }
            if d.isAIGenerated == true {
                previewChip("AI", icon: "sparkles", variant: .ai)
            }
        }
        .allowsHitTesting(false)
    }

    private enum PreviewChipVariant { case regular, ai }

    private func previewChip(_ text: String, icon: String?, variant: PreviewChipVariant) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.4)
        }
        .foregroundStyle(variant == .ai ? Color.white : Color.chipInk)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(
                variant == .ai
                ? Color.chipAI.opacity(0.85)
                : Color.white.opacity(0.78)
            )
        )
    }

    private func isLive(detail d: WallpaperDetail) -> Bool {
        d.isDynamic || isVideo(detail: d)
    }

    private func isVideo(detail d: WallpaperDetail) -> Bool {
        d.fileType.lowercased().hasPrefix("video/")
    }

    private func fullscreenResolutionName(_ d: WallpaperDetail) -> String {
        switch max(d.width, d.height) {
        case 7680...: return "8K UHD"
        case 3840...: return "4K UHD"
        case 2560...: return "QHD/2K"
        case 1920...: return "Full HD"
        case 1280...: return "HD"
        default: return d.resolutionLabel
        }
    }

    private func rawHeroSize(detail: WallpaperDetail, layout: DetailLayout) -> CGSize {
        let maxWidth = max(1, layout.contentWidth - layout.stagePadding * 2)
        let maxHeight = layout.heroMaxHeight
        let sourceWidth = CGFloat(max(detail.width, 1))
        let sourceHeight = CGFloat(max(detail.height, 1))
        let aspect = sourceWidth / sourceHeight

        if maxWidth / maxHeight > aspect {
            return CGSize(width: maxHeight * aspect, height: maxHeight)
        }
        return CGSize(width: maxWidth, height: maxWidth / aspect)
    }

    private static let previewOptions: [PreviewMode] = [.off, .plain, .home, .lock]

    private func detailActionOverlay(detail d: WallpaperDetail?, layout: DetailLayout) -> some View {
        VStack(alignment: .center, spacing: 12) {
            if let d {
                downloadNoticeView(detail: d, layout: layout)

                if showingCollectionPicker {
                    collectionPicker(detail: d, layout: layout)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if showingWallpaperPicker {
                    wallpaperPicker(detail: d, layout: layout)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            actionBar(detail: d, wallpaper: initialWallpaper, layout: layout)
        }
        .frame(maxWidth: layout.actionBarAvailableWidth, alignment: .center)
        .padding(.horizontal, layout.overlayHorizontalPadding)
        .padding(.bottom, layout.overlayBottomPadding)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .bottom)
    }

    private func actionBar(detail: WallpaperDetail?, wallpaper: Wallpaper?, layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                actionRowsWide(detail: detail, wallpaper: wallpaper)
                actionRowsMedium(detail: detail, wallpaper: wallpaper)
                actionRowsCompact(detail: detail, wallpaper: wallpaper)
                actionRowsMinimal(detail: detail, wallpaper: wallpaper)
            }
        }
        .animation(.easeOut(duration: 0.16), value: showingWallpaperPicker)
        .animation(.easeOut(duration: 0.16), value: showingCollectionPicker)
        .padding(layout.isCompact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
        .glassSurface(
            RoundedRectangle(cornerRadius: 30, style: .continuous),
            tone: .dark,
            lighting: 0.72
        )
        .shadow(color: Color.black.opacity(0.30), radius: 26, y: 10)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ActionBarWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
    }

    private func actionRowsWide(detail: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        HStack(spacing: 8) {
            actionBarMeta(detail: detail, wallpaper: wallpaper)
                .fixedSize(horizontal: true, vertical: false)
            divider
            socialActions(detail: detail, wallpaper: wallpaper)
                .fixedSize(horizontal: true, vertical: false)
            divider
            fullscreenAction(detail: detail)
            downloadActions(detail: detail, wallpaper: wallpaper)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func actionRowsMedium(detail: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                actionBarMeta(detail: detail, wallpaper: wallpaper)
                divider
                socialActions(detail: detail, wallpaper: wallpaper)
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 8) {
                fullscreenAction(detail: detail)
                downloadActions(detail: detail, wallpaper: wallpaper)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func actionRowsCompact(detail: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            actionBarMeta(detail: detail, wallpaper: wallpaper)
            HStack(spacing: 8) {
                socialActions(detail: detail, wallpaper: wallpaper)
                if detail.map({ !isVideo(detail: $0) }) ?? true {
                    divider
                    fullscreenAction(detail: detail)
                }
            }
            downloadActions(detail: detail, wallpaper: wallpaper)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionRowsMinimal(detail: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            actionBarMeta(detail: detail, wallpaper: wallpaper)
            HStack(spacing: 8) {
                fullscreenAction(detail: detail)
                downloadActions(detail: detail, wallpaper: wallpaper)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionBarMeta(detail d: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        if let d {
            actionBarMetaText(
                dimensions: "\(d.width.formatted()) × \(d.height.formatted())",
                specs: metaSpecText(detail: d)
            )
        } else if let wallpaper {
            actionBarMetaText(
                dimensions: "\(wallpaper.width.formatted()) × \(wallpaper.height.formatted())",
                specs: [wallpaper.resolutionLabel, wallpaper.fileType.uppercased(), byteString(wallpaper.fileSize)]
                    .joined(separator: " · ")
            )
        } else {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 104, height: 13)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 168, height: 9)
            }
            .frame(width: 210, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    private func actionBarMetaText(dimensions: String, specs: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dimensions)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .lineLimit(1)
            Text(specs)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 210, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func toolbarMeta(detail d: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        HStack(spacing: 10) {
            if let d {
                toolbarMetaItem(icon: "rectangle", text: "\(d.width.formatted())×\(d.height.formatted())")
                toolbarMetaItem(icon: "externaldrive", text: byteString(d.fileSize))
                if isVideo(detail: d), let videoDuration {
                    toolbarMetaItem(icon: "clock", text: formatDuration(videoDuration))
                }
            } else if let wallpaper {
                if wallpaper.width > 0, wallpaper.height > 0 {
                    toolbarMetaItem(icon: "rectangle", text: "\(wallpaper.width.formatted())×\(wallpaper.height.formatted())")
                } else {
                    toolbarMetaSkeletonItem(icon: "rectangle", width: 64)
                }
                if wallpaper.fileSize > 0 {
                    toolbarMetaItem(icon: "externaldrive", text: byteString(wallpaper.fileSize))
                } else {
                    toolbarMetaSkeletonItem(icon: "externaldrive", width: 48)
                }
            } else {
                toolbarMetaSkeletonItem(icon: "rectangle", width: 64)
                toolbarMetaSkeletonItem(icon: "externaldrive", width: 48)
            }
        }
    }

    private func toolbarMetaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.mono10)
                .tracking(0.4)
                .monospacedDigit()
        }
        .foregroundStyle(Color.white.opacity(0.72))
        .lineLimit(1)
    }

    private func toolbarMetaSkeletonItem(icon: String, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .frame(width: width, height: 9)
        }
        .foregroundStyle(Color.white.opacity(0.58))
        .lineLimit(1)
    }

    private func socialActions(detail: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        let likeCount = detail?.likeCount ?? wallpaper?.likeCount
        let hasDetail = detail != nil
        return HStack(spacing: 6) {
            actionPill(icon: isLiked ? "heart.fill" : "heart", label: isLiked ? L10n.detail.liked : L10n.detail.like, count: likeCount.map { "\($0)" }, on: isLiked) {
                if let detail {
                    Task { await toggleLike(detail) }
                }
            }
            .allowsHitTesting(hasDetail)
            actionPill(icon: isFavorited ? "star.fill" : "star", label: isFavorited ? L10n.detail.saved : L10n.detail.favorite, count: nil, on: isFavorited) {
                if let detail {
                    Task { await toggleFavorite(detail) }
                }
            }
            .allowsHitTesting(hasDetail)
            addToListMenu(detail)
        }
    }

    @ViewBuilder
    private func fullscreenAction(detail: WallpaperDetail?) -> some View {
        if detail.map({ !isVideo(detail: $0) }) ?? true {
            let ready = detail.map(downloadReady) ?? false
            Button {
                guard let detail, !isVideo(detail: detail), downloadReady(detail) else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    showingCollectionPicker = false
                    showingWallpaperPicker = false
                    showingFullscreenPreview = true
                }
            } label: {
                WebFullscreenIconShape()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 15, height: 15)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(GlassBounceButtonStyle())
            .disabled(!ready)
            .opacity(ready ? 1 : 0.48)
            .help(L10n.detail.fullscreenPreview)
        }
    }

    private var previewModePicker: some View {
        GlassSegmented(
            segments: Self.previewOptions.map { GlassSegment(id: $0, label: previewModeLabel($0)) },
            selection: $mode,
            tone: .light,
            compact: true
        )
    }

    private func downloadActions(detail: WallpaperDetail?, wallpaper: Wallpaper?) -> some View {
        let downloading = detail.map { manager.downloading.contains($0.id) } ?? false
        let downloaded = detail.map { isLocalDownloaded($0) } ?? isLocalDownloaded(wallpaper)
        let hasDetail = detail != nil
        let ready = detail.map(downloadReady) ?? false
        return HStack(spacing: 6) {
            Button(action: {
                if let detail {
                    Task { await downloadOriginal(detail) }
                }
            }) {
                downloadLabel(icon: downloaded ? .system("checkmark.circle") : .webDownload,
                              text: downloadButtonText(detail: detail, downloaded: downloaded, downloading: downloading),
                              emphasized: true)
            }
            .disabled(!(hasDetail && ready && !downloading && !downloaded))
            .opacity(ready ? 1 : 0.55)
            .buttonStyle(.plain)
            Button(action: {
                guard detail != nil else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    showingCollectionPicker = false
                    showingWallpaperPicker.toggle()
                }
            }) {
                downloadLabel(icon: .system(downloaded ? "display" : "rectangle.on.rectangle.angled"),
                              text: downloadAndSetButtonText(detail: detail, downloaded: downloaded),
                              emphasized: false)
            }
            .disabled(!(hasDetail && ready && !downloading && !applyingWallpaper))
            .opacity(ready ? 1 : 0.55)
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
        }
    }

    private func resolvedActionBarWidth(layout: DetailLayout) -> CGFloat {
        let fallback = min(layout.actionBarAvailableWidth, layout.isCompact ? 620 : 720)
        let measured = measuredActionBarWidth > 0 ? measuredActionBarWidth : fallback
        return min(max(320, measured), layout.actionBarAvailableWidth)
    }

    private func wallpaperPicker(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        let targets = WallpaperManager.displayTargets()
        let activeTargetID = targets.contains { $0.id == selectedDisplayTargetID }
            ? selectedDisplayTargetID
            : WallpaperDisplayTarget.allID
        let cannotApply = applyingWallpaper || manager.downloading.contains(d.id)
            || surfaceUnavailable(selectedWallpaperSurface, detail: d) || !downloadReady(d)

        return VStack(alignment: .leading, spacing: 14) {
            if selectedWallpaperSurface != .lockScreen {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(L10n.detail.wallpaperChooseDisplay)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showingWallpaperPicker = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.66))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 10, alignment: .top)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(targets) { target in
                            displayTargetButton(target: target, selected: activeTargetID == target.id)
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Spacer(minLength: 8)
                Button {
                    Task { await applySelectedWallpaper(d) }
                } label: {
                    HStack(spacing: 7) {
                        if applyingWallpaper || manager.downloading.contains(d.id) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(applyingWallpaper || manager.downloading.contains(d.id) ? L10n.detail.wallpaperApplying : L10n.detail.wallpaperApply)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(cannotApply ? Color.white.opacity(0.20) : Color.accent))
                }
                .buttonStyle(.plain)
                .disabled(cannotApply)
                .help(surfaceUnavailable(selectedWallpaperSurface, detail: d) ? surfaceUnavailableReason(selectedWallpaperSurface, detail: d) : L10n.detail.wallpaperApply)
            }
        }
        .padding(14)
        .frame(width: resolvedActionBarWidth(layout: layout), alignment: .leading)
        .glassPanel(cornerRadius: 18)
    }

    private func collectionPicker(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.detail.addToList)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        showingCollectionPicker = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.66))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            if !auth.isLoggedIn {
                Button {
                    auth.login()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text(L10n.browse.signInPrompt(L10n.detail.addToList))
                            .lineLimit(2)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                if myCollections.isEmpty {
                    Text(L10n.detail.noCollections)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.64))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                } else {
                    ScrollView(.vertical, showsIndicators: myCollections.count > 4) {
                        VStack(spacing: 8) {
                            ForEach(myCollections) { collection in
                                collectionPickerRow(collection: collection, detail: d)
                            }
                        }
                    }
                    .frame(maxHeight: 210)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        collectionTitleField

                        Button {
                            Task { await createCollectionAndAddWallpaper(d) }
                        } label: {
                            HStack(spacing: 6) {
                                if creatingCollection {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(creatingCollection ? L10n.collections.creating : L10n.collections.create)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(Capsule().fill(canCreateCollection ? Color.accent : Color.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCreateCollection || creatingCollection)
                    }

                    if let collectionError {
                        Text(collectionError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.warn.opacity(0.90))
                    }
                }
            }
        }
        .padding(14)
        .frame(width: resolvedActionBarWidth(layout: layout), alignment: .leading)
        .glassPanel(cornerRadius: 18)
    }

    private var canCreateCollection: Bool {
        !newCollectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isShowingDetailActionPopup: Bool {
        showingWallpaperPicker || showingCollectionPicker
    }

    private var collectionTitleField: some View {
        ZStack(alignment: .leading) {
            if newCollectionTitle.isEmpty && !collectionTitleFocused {
                Text(L10n.collections.titlePlaceholder)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.44))
                    .padding(.leading, 11)
                    .allowsHitTesting(false)
            }

            TextField("", text: $newCollectionTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.92))
                .tint(Color.white.opacity(0.90))
                .colorScheme(.dark)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .focused($collectionTitleFocused)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.20)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func collectionPickerRow(collection: CollectionBrief, detail d: WallpaperDetail) -> some View {
        let contains = collection.containsWallpaper == true
        return Button {
            Task { await addWallpaper(d, to: collection) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(contains ? Color.accent.opacity(0.22) : Color.white.opacity(0.08))
                    Image(systemName: contains ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(contains ? Color.accent : Color.white.opacity(0.72))
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                    Text(L10n.collections.wallpaperCountCaps(collection.wallpaperCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(contains ? Color.accent.opacity(0.74) : Color.white.opacity(0.50))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(contains ? Color.accent.opacity(0.10) : Color.white.opacity(0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(contains ? Color.accent.opacity(0.34) : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func actionPopupDismissLayer(layout: DetailLayout) -> some View {
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .frame(width: layout.size.width, height: layout.size.height)
            .onTapGesture {
                dismissDetailActionPopups()
            }
    }

    private func dismissDetailActionPopups() {
        withAnimation(.easeOut(duration: 0.16)) {
            showingWallpaperPicker = false
            showingCollectionPicker = false
            collectionError = nil
        }
    }

    private func displayTargetButton(target: WallpaperDisplayTarget, selected: Bool) -> some View {
        Button {
            selectedDisplayTargetID = target.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: target.isAll ? "rectangle.on.rectangle" : "display")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selected ? Color.accent : Color.white.opacity(0.62))
                    if selected {
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                    Text(target.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Color.accent.opacity(0.20) : Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Color.accent.opacity(0.70) : Color.white.opacity(0.12), lineWidth: selected ? 1.4 : 1))
        }
        .buttonStyle(.plain)
    }

    private func surfaceUnavailable(_ surface: WallpaperApplySurface, detail d: WallpaperDetail) -> Bool {
        switch surface {
        case .desktop:
            return false
        case .lockScreen, .both:
            return true
        }
    }

    private func surfaceUnavailableReason(_ surface: WallpaperApplySurface, detail d: WallpaperDetail) -> String {
        switch surface {
        case .desktop:
            return L10n.detail.wallpaperApply
        case .lockScreen, .both:
            return L10n.detail.lockScreenUnavailable
        }
    }

    private enum DetailActionIcon {
        case system(String)
        case webDownload
    }

    private func downloadLabel(icon: DetailActionIcon, text: String, emphasized: Bool) -> some View {
        HStack(spacing: emphasized ? 7 : 6) {
            Group {
                switch icon {
                case .system(let systemName):
                    Image(systemName: systemName)
                case .webDownload:
                    WebDownloadIconShape()
                }
            }
            .font(.system(size: emphasized ? 12 : 11, weight: emphasized ? .semibold : .medium))
            .frame(width: emphasized ? 13 : 12, height: emphasized ? 13 : 12)
            Text(text)
                .font(.system(size: emphasized ? 12 : 11, weight: emphasized ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, emphasized ? 16 : 11).padding(.vertical, emphasized ? 8 : 6)
        .background(Capsule().fill(emphasized ? Color.accent : Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(emphasized ? Color.clear : Color.white.opacity(0.16), lineWidth: 1))
        .shadow(color: emphasized ? Color.accent.opacity(0.45) : Color.clear, radius: emphasized ? 10 : 0, y: emphasized ? 4 : 0)
    }

    // File info row inside the toolbar (web .wd-actionbar-meta): big
    // dimensions + mono "res · TYPE · size". Content tags live on the
    // preview image itself, matching the list tiles.
    private func metaRow(detail d: WallpaperDetail) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metaDimensions(detail: d)
                metaSpecs(detail: d)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    metaDimensions(detail: d)
                    Spacer(minLength: 0)
                }
                metaSpecs(detail: d)
            }
        }
    }

    private func metaDimensions(detail d: WallpaperDetail) -> some View {
        Text("\(d.width.formatted()) × \(d.height.formatted())")
            .font(.system(size: 15, weight: .medium, design: .serif))
            .foregroundStyle(Color.ink)
            .fixedSize()
    }

    private func metaSpecs(detail d: WallpaperDetail) -> some View {
        Text(metaSpecText(detail: d))
            .font(.system(size: 11, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(Color.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func metaSpecText(detail d: WallpaperDetail) -> String {
        var parts = [d.resolutionLabel, d.fileType.uppercased(), byteString(d.fileSize)]
        if isVideo(detail: d), let videoDuration {
            parts.append(formatDuration(videoDuration))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func actionPill(icon: String, label: String, count: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.sans11)
                if let c = count {
                    Text(c).font(.mono10).tracking(0.4).foregroundStyle(Color.white.opacity(0.70))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.13)))
                }
            }
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.90))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(on ? Color.accent.opacity(0.22) : Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(on ? Color.accent.opacity(0.75) : Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(GlassBounceButtonStyle())
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 26)
    }

    private func metaGrid(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        VStack(spacing: 0) {
            statsStrip(detail: detail, layout: layout)
            if layout.isTight {
                VStack(alignment: .leading, spacing: 18) {
                    uploaderCell(detail: detail)
                    Rectangle().fill(Color.hair).frame(height: 1)
                    aboutCell(detail: detail)
                    Rectangle().fill(Color.hair).frame(height: 1)
                    paletteCell(detail: detail)
                }
                .padding(layout.metaPadding)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    uploaderCell(detail: detail)
                    aboutCell(detail: detail)
                    paletteCell(detail: detail)
                }
                .padding(layout.metaPadding)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hair, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statsStrip(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        if layout.isCompact {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                statCell(label: L10n.detail.statDownloads, value: "\(detail.downloadCount)")
                statCell(label: L10n.detail.statLikes, value: "\(detail.likeCount)")
                statCell(label: L10n.detail.statFavorited, value: "\(detail.favoriteCount)")
                statCell(label: L10n.detail.statViews, value: "\(detail.viewCount)")
            }
            .padding(.horizontal, 4).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
        } else {
            HStack(spacing: 0) {
                statCell(label: L10n.detail.statDownloads, value: "\(detail.downloadCount)")
                divider
                statCell(label: L10n.detail.statLikes, value: "\(detail.likeCount)")
                divider
                statCell(label: L10n.detail.statFavorited, value: "\(detail.favoriteCount)")
                divider
                statCell(label: L10n.detail.statViews, value: "\(detail.viewCount)")
            }
            .padding(.horizontal, 4).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: label)
            Text(value).font(.displayLg).foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
    }

    private func uploaderCell(detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: L10n.detail.uploadedBy)
            if let u = detail.uploader {
                Button(action: { onUploader(u.username) }) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.paper2).frame(width: 40, height: 40)
                            .overlay(Text(String((u.nickname?.isEmpty == false ? u.nickname! : u.username).prefix(1)).uppercased()).font(.displayLg).foregroundStyle(Color.ink))
                            .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(u.username)").font(.sans13).foregroundStyle(Color.ink)
                            Text(L10n.detail.viewProfile).font(.kicker).tracking(2).foregroundStyle(Color.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(L10n.detail.unknownUploader).font(.sans13).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aboutCell(detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: L10n.detail.about)
            Text(L10n.detail.wallpaperTitle)
                .font(.displayLg).foregroundStyle(Color.ink)
            if let tags = detail.tags, !tags.isEmpty {
                ChipFlow {
                    ForEach(Array(tags.enumerated()), id: \.offset) { i, t in
                        let palette = detail.paletteList
                        let baseHex = palette.isEmpty ? "#888" : palette[i % palette.count]
                        let c = Color(hex: baseHex)
                        HStack(spacing: 4) {
                            Circle().fill(c).frame(width: 6, height: 6)
                            Text(t.name).font(.sans11)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(c.blended(with: Color.ink, fraction: 0.4))
                        .background(Capsule().fill(c.opacity(0.12)))
                        .overlay(Capsule().stroke(c, lineWidth: 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paletteCell(detail: WallpaperDetail) -> some View {
        let pal = detail.paletteList
        return VStack(alignment: .leading, spacing: 10) {
            Kicker(text: pal.isEmpty ? L10n.detail.palette : L10n.detail.paletteColors(pal.count))
            if pal.isEmpty {
                Rectangle().fill(Color.paper2).frame(height: 44).cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hair, lineWidth: 0.5))
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(pal.enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex))
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hair, lineWidth: 0.5))
                    }
                }
            }
            if let dc = detail.dominantColor {
                HStack(spacing: 6) {
                    Rectangle().fill(Color(hex: dc)).frame(width: 12, height: 12).cornerRadius(2)
                    Text(L10n.detail.dominant(dc.uppercased()))
                        .font(.kicker).tracking(2).foregroundStyle(Color.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moreLikeThis(layout: DetailLayout, dark: Bool = false) -> some View {
        let titleColor = dark ? Color.lightText : Color.ink
        let mutedColor = dark ? Color.lightText.opacity(0.54) : Color.muted
        let dividerColor = dark ? Color.white.opacity(0.12) : Color.hair
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Kicker(text: L10n.detail.relatedArchive, tint: mutedColor)
                    Text(L10n.detail.moreLikeThis)
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(titleColor)
                        .tracking(-0.3)
                }
                Spacer()
                Text(L10n.detail.picksCount(similar.count))
                    .font(.mono10)
                    .tracking(1.4)
                    .foregroundStyle(mutedColor)
                    .lineLimit(1)
            }
            Rectangle().fill(dividerColor).frame(height: 1)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                    count: layout.recommendationColumns
                ),
                spacing: 14
            ) {
                ForEach(similar) { wp in
                    Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp) }
                        .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // ─── Actions ────────────────────────────────────────────────
    private func isOwner(_ detail: WallpaperDetail) -> Bool {
        auth.user?.id == detail.userID
    }

    private func requiresTrade(_ detail: WallpaperDetail) -> Bool {
        !isOwner(detail) && detail.isDownloaded != true && !isLocalDownloaded(detail)
    }

    private func downloadButtonText(detail: WallpaperDetail, downloaded: Bool, downloading: Bool) -> String {
        if downloaded { return L10n.detail.gotIt }
        if downloading { return L10n.detail.downloading }
        return requiresTrade(detail) ? L10n.detail.tradeForOne : L10n.detail.download
    }

    private func downloadButtonText(detail: WallpaperDetail?, downloaded: Bool, downloading: Bool) -> String {
        if let detail {
            return downloadButtonText(detail: detail, downloaded: downloaded, downloading: downloading)
        }
        if downloaded { return L10n.detail.gotIt }
        if downloading { return L10n.detail.downloading }
        return L10n.detail.download
    }

    private func downloadAndSetButtonText(detail: WallpaperDetail, downloaded: Bool) -> String {
        if downloaded { return L10n.detail.setAsWallpaper }
        return requiresTrade(detail) ? L10n.detail.downloadAndSetCoin : L10n.detail.downloadAndSet
    }

    private func downloadAndSetButtonText(detail: WallpaperDetail?, downloaded: Bool) -> String {
        if let detail {
            return downloadAndSetButtonText(detail: detail, downloaded: downloaded)
        }
        if downloaded { return L10n.detail.setAsWallpaper }
        return L10n.detail.downloadAndSet
    }

    private func isLocalDownloaded(_ detail: WallpaperDetail) -> Bool {
        manager.localURL(for: detail.id) != nil
    }

    private func isLocalDownloaded(_ wallpaper: Wallpaper?) -> Bool {
        guard let wallpaper else { return false }
        return manager.localURL(for: wallpaper.id) != nil
    }

    private func refreshCoinsIfTradeRequired(_ detail: WallpaperDetail) async {
        if requiresTrade(detail) {
            await auth.refreshCoins()
        }
    }

    private func downloadOriginal(_ detail: WallpaperDetail) async {
        if isLocalDownloaded(detail) {
            downloadNotice = .success
            return
        }
        guard auth.isLoggedIn else {
            downloadNotice = .failed(L10n.detail.signInToDownload)
            auth.login()
            return
        }
        await refreshCoinsIfTradeRequired(detail)
        downloadNotice = nil
        do {
            try await manager.downloadOriginal(wallpaper: lightWallpaper(detail))
            await auth.refreshProfile()
            downloadNotice = .success
        } catch {
            handleDownloadError(error)
        }
    }

    private func applySelectedWallpaper(_ detail: WallpaperDetail) async {
        guard !surfaceUnavailable(selectedWallpaperSurface, detail: detail) else {
            downloadNotice = .failed(surfaceUnavailableReason(selectedWallpaperSurface, detail: detail))
            return
        }
        let wallpaper = lightWallpaper(detail)
        guard auth.isLoggedIn || isLocalDownloaded(detail) else {
            downloadNotice = .failed(L10n.detail.signInToDownloadAndSet)
            auth.login()
            return
        }

        applyingWallpaper = true
        downloadNotice = nil
        defer { applyingWallpaper = false }

        do {
            if !isLocalDownloaded(detail) {
                await refreshCoinsIfTradeRequired(detail)
                try await manager.downloadOriginal(wallpaper: wallpaper)
            }
            let target = selectedDisplayTarget()
            try await manager.setAsWallpaper(wallpaper, target: target, surface: selectedWallpaperSurface)
            await auth.refreshProfile()
            downloadNotice = .set
            withAnimation(.easeOut(duration: 0.16)) {
                showingWallpaperPicker = false
            }
        } catch {
            handleDownloadError(error)
        }
    }

    private func handleDownloadError(_ error: Error) {
        if let api = error as? APIError {
            switch api {
            case .insufficientCoins:
                downloadNotice = .insufficientCoins
            case .unauthorized:
                downloadNotice = .failed(L10n.detail.signInAgain)
                auth.login()
            case .serverError(let code, let message):
                if code == 404 || code == 409 || code == 423 {
                    downloadNotice = .unavailable
                } else {
                    downloadNotice = .failed(message.isEmpty ? L10n.detail.serverCouldNotPrepare : message)
                }
            default:
                downloadNotice = .failed(api.errorDescription ?? L10n.detail.downloadFailedFallback)
            }
        } else {
            downloadNotice = .failed(error.localizedDescription.isEmpty ? L10n.detail.downloadFailedFallback : error.localizedDescription)
        }
    }

    private func load() async {
        detail = nil
        loadError = nil
        heroOriginalLoaded = false
        downloadNotice = nil
        infoActionMessage = nil
        similar = []
        similarLoaded = false
        showingWallpaperPicker = false
        showingCollectionPicker = false
        showingFullscreenPreview = false
        collectionError = nil
        isLiked = initialWallpaper?.isLiked ?? false
        isFavorited = initialWallpaper?.isFavorited ?? false
        videoDurationTask?.cancel()
        videoDuration = nil
        do {
            let d = try await APIClient.shared.fetchWallpaperDetail(slug: detailRequestKey)
            detail = d
            isLiked = d.isLiked ?? false
            isFavorited = d.isFavorited ?? false
            if surfaceUnavailable(selectedWallpaperSurface, detail: d) {
                selectedWallpaperSurface = .desktop
            }
            loadVideoDurationIfNeeded(detail: d)
            await loadCategoriesIfNeeded()
            await loadCollections(wallpaperID: d.id)
        } catch {
            loadError = error.localizedDescription
            similarLoaded = true
        }
    }

    private func selectedDisplayTarget() -> WallpaperDisplayTarget {
        let targets = WallpaperManager.displayTargets()
        return targets.first { $0.id == selectedDisplayTargetID } ?? targets.first ?? WallpaperDisplayTarget(
            id: WallpaperDisplayTarget.allID,
            name: L10n.detail.wallpaperAllDisplays,
            detail: L10n.detail.wallpaperAllDisplaysDetail(0),
            screenKey: nil,
            isMain: false
        )
    }

    private func loadVideoDurationIfNeeded(detail d: WallpaperDetail) {
        videoDurationTask?.cancel()
        videoDuration = nil
        guard isVideo(detail: d) else { return }
        videoDurationTask = Task {
            await loadVideoDuration(detail: d)
        }
    }

    private func loadVideoDuration(detail d: WallpaperDetail) async {
        let rawURL = d.previewVideoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = rawURL?.isEmpty == false ? (rawURL ?? d.originalURL) : d.originalURL
        guard let url = URL(string: source) else { return }
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0, !Task.isCancelled else { return }
            await MainActor.run {
                if detail?.id == d.id {
                    videoDuration = seconds
                }
            }
        } catch {
            // Duration is a nice-to-have meta field; leave it hidden if the
            // preview resource cannot expose timing metadata.
        }
    }

    private func loadSimilar(limit: Int) async {
        guard let detail else {
            similarLoaded = false
            return
        }
        let detailID = detail.id
        similarLoaded = false
        do {
            let wallpapers = try await APIClient.shared.fetchSimilarWallpapers(wallpaperID: detailID, limit: limit)
            guard self.detail?.id == detailID else { return }
            similar = wallpapers
            similarLoaded = true
        } catch {
            guard self.detail?.id == detailID else { return }
            similar = []
            similarLoaded = true
        }
    }

    private func loadCategoriesIfNeeded() async {
        guard categories.isEmpty else { return }
        if let list = try? await APIClient.shared.fetchCategories() {
            categories = list
        }
    }

    private func toggleLike(_ d: WallpaperDetail) async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isLiked
        isLiked.toggle()
        do {
            if prev {
                try await APIClient.shared.unlike(wallpaperID: d.id)
            } else {
                try await APIClient.shared.like(wallpaperID: d.id)
            }
        } catch {
            isLiked = prev  // revert on failure
        }
    }
    private func toggleFavorite(_ d: WallpaperDetail) async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isFavorited
        isFavorited.toggle()
        do {
            if prev {
                try await APIClient.shared.unfavorite(wallpaperID: d.id)
            } else {
                try await APIClient.shared.favorite(wallpaperID: d.id)
            }
        } catch {
            isFavorited = prev
        }
    }

    private func reportWallpaper(_ d: WallpaperDetail) async {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        guard !reportingWallpaper else { return }
        reportingWallpaper = true
        infoActionMessage = nil
        defer { reportingWallpaper = false }
        do {
            try await APIClient.shared.reportWallpaper(wallpaperID: d.id, reason: "other", note: "Reported from macOS client.")
            infoActionMessage = L10n.detail.reported
        } catch let error as APIError {
            if case .unauthorized = error {
                auth.login()
            }
            infoActionMessage = L10n.detail.reportFailed
        } catch {
            infoActionMessage = L10n.detail.reportFailed
        }
    }

    private func deleteWallpaper(_ d: WallpaperDetail) async {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        guard isOwner(d), !deletingWallpaper else { return }
        deletingWallpaper = true
        infoActionMessage = nil
        defer { deletingWallpaper = false }
        do {
            try await APIClient.shared.deleteWallpaper(wallpaperID: d.id)
            manager.deleteLocal(d.id)
            infoActionMessage = L10n.detail.deleteSucceeded
            closeOrDismiss()
        } catch let error as APIError {
            if case .unauthorized = error {
                auth.login()
            }
            infoActionMessage = L10n.detail.deleteFailed
        } catch {
            infoActionMessage = L10n.detail.deleteFailed
        }
    }

    // Reconstruct a lightweight Wallpaper from a WallpaperDetail so we
    // can hand it to WallpaperManager (which expects the popover shape).
    // "Add to list" — a menu of the user's collections (checkmark on the
    // ones already containing this wallpaper). Mirrors the web's
    // AddToCollectionModal entry point.
    private func addToListMenu(_ detail: WallpaperDetail?) -> some View {
        Button {
            if let detail {
                toggleCollectionPicker(detail)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                Text(L10n.detail.addToList).font(.sans11)
            }
            .foregroundStyle(Color.white.opacity(0.90))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(GlassBounceButtonStyle())
        .fixedSize()
        .allowsHitTesting(detail != nil)
    }

    private func toggleCollectionPicker(_ detail: WallpaperDetail) {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            showingWallpaperPicker = false
            showingCollectionPicker.toggle()
            collectionError = nil
        }
        Task { await loadCollections(wallpaperID: detail.id) }
    }

    private func addWallpaper(_ detail: WallpaperDetail, to collection: CollectionBrief) async {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        guard collection.containsWallpaper != true else { return }
        collectionError = nil
        do {
            try await APIClient.shared.addToCollection(collectionID: collection.id, wallpaperID: detail.id)
            await loadCollections(wallpaperID: detail.id)
        } catch {
            collectionError = L10n.collections.createFailed
        }
    }

    private func createCollectionAndAddWallpaper(_ detail: WallpaperDetail) async {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        let title = newCollectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !creatingCollection else { return }
        creatingCollection = true
        collectionError = nil
        defer { creatingCollection = false }
        do {
            let collection = try await APIClient.shared.createCollection(title: title, isPublic: true)
            try await APIClient.shared.addToCollection(collectionID: collection.id, wallpaperID: detail.id)
            newCollectionTitle = ""
            await loadCollections(wallpaperID: detail.id)
        } catch {
            collectionError = L10n.collections.createFailed
        }
    }

    private func loadCollections(wallpaperID: Int) async {
        guard auth.isLoggedIn else { return }
        if let list = try? await APIClient.shared.fetchMyCollections(wallpaperID: wallpaperID) {
            myCollections = list
        }
    }

    private func lightWallpaper(_ d: WallpaperDetail) -> Wallpaper {
        Wallpaper(
            id: d.id, slug: d.slug, userID: d.userID, categoryID: d.categoryID, title: d.title,
            description: d.description ?? "", originalURL: d.originalURL, thumbURL: d.thumbURL,
            previewURL: d.previewURL, width: d.width, height: d.height, fileSize: d.fileSize,
            fileType: d.fileType, dominantColor: d.dominantColor, colorPalette: d.colorPalette, status: 1,
            viewCount: d.viewCount, likeCount: d.likeCount, downloadCount: d.downloadCount,
            favoriteCount: d.favoriteCount, isDynamic: d.isDynamic, isAIGenerated: d.isAIGenerated,
            isLiked: d.isLiked, isFavorited: d.isFavorited, isDownloaded: d.isDownloaded,
            createdAt: d.createdAt
        )
    }
}

private struct ActionBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DynamicFramePreview: View {
    let frameURLs: [URL]
    let posterURL: URL?
    let dominantColor: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameIndex = 0
    @State private var playing = true
    @State private var hover = false

    var body: some View {
        ZStack {
            Color(hex: dominantColor ?? "#111")

            CachedAsyncImage(url: posterURL, maxPixelDimension: 1400) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(hex: dominantColor ?? "#111")
            }
            .clipped()

            ForEach(Array(frameURLs.enumerated()), id: \.offset) { index, url in
                CachedAsyncImage(url: url, maxPixelDimension: 1800) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .opacity(index == visibleFrameIndex ? 1 : 0)
                .clipped()
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    playbackControl
                }
                .padding(.trailing, 22)
                .padding(.bottom, 18)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: visibleFrameIndex)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onAppear {
            if reduceMotion {
                playing = false
            }
            clampFrameIndex()
        }
        .onChange(of: frameURLs) { _, _ in
            clampFrameIndex()
        }
        .task(id: playbackTaskID) {
            await runPlaybackLoop()
        }
    }

    private var visibleFrameIndex: Int {
        guard !frameURLs.isEmpty else { return 0 }
        return min(max(frameIndex, 0), frameURLs.count - 1)
    }

    private var playbackTaskID: String {
        "\(playing)-\(reduceMotion)-\(frameURLs.map(\.absoluteString).joined(separator: "|"))"
    }

    private var playbackControl: some View {
        Button {
            playing.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 10)
                Text("\(L10n.detail.chipLive) · \(visibleFrameIndex + 1)/\(max(frameURLs.count, 1))")
                    .font(.mono10)
                    .tracking(0.7)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(hover || !playing ? 0.70 : 0.52))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .help(playing ? L10n.detail.pausePreview : L10n.detail.playPreview)
    }

    private func runPlaybackLoop() async {
        guard playing, !reduceMotion, frameURLs.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                frameIndex = (visibleFrameIndex + 1) % frameURLs.count
            }
        }
    }

    private func clampFrameIndex() {
        guard !frameURLs.isEmpty else {
            frameIndex = 0
            return
        }
        frameIndex = min(max(frameIndex, 0), frameURLs.count - 1)
    }
}

private struct LiveVideoPreview: View {
    let sourceURL: URL
    let posterURL: URL?
    let dominantColor: String?

    @State private var player: AVPlayer?
    @State private var localURL: URL?
    @State private var loadTask: Task<Void, Never>?
    @State private var endObserver: NSObjectProtocol?
    @State private var buffering = false
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var hover = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black
            CachedAsyncImage(url: posterURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(hex: dominantColor ?? "#111")
            }
            .clipped()
            .opacity(player == nil ? 1 : 0)

            InlineAVPlayerView(player: player)
                .opacity(player == nil ? 0 : 1)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.26)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Button(action: togglePlayback) {
                ZStack {
                    if buffering {
                        bufferingHUD
                    } else {
                        playButton
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(buffering)
            .help(playing ? L10n.detail.pausePreview : L10n.detail.playPreview)
            .onHover { hover = $0 }

            if let errorMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(errorMessage)
                            .font(.mono10)
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.58)))
                    .padding(.bottom, 14)
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onDisappear { cleanup() }
        .onChange(of: sourceURL) { _, _ in cleanup() }
    }

    private var playButton: some View {
        Circle()
            .fill(Color.black.opacity(0.58))
            .frame(width: 52, height: 52)
            .overlay(
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .offset(x: playing ? 0 : 1.5)
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.32), radius: 12, x: 0, y: 5)
            .scaleEffect(hover ? 1.06 : 1.0)
            .opacity(playing && !hover ? 0 : 1)
            .animation(.easeOut(duration: 0.18), value: hover)
            .animation(.easeOut(duration: 0.18), value: playing)
    }

    private var bufferingHUD: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(8, proxy.size.width * CGFloat(max(0, min(progress, 1)))))
                }
            }
            .frame(width: 150, height: 6)

            Text("\(Int(max(0, min(progress, 1)) * 100))%")
                .font(.mono11)
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.92))
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func togglePlayback() {
        errorMessage = nil
        if localURL == nil {
            startBuffering()
            return
        }
        guard let player else { return }
        if playing {
            player.pause()
            playing = false
        } else {
            player.play()
            playing = true
        }
    }

    private func startBuffering() {
        guard !buffering else { return }
        buffering = true
        progress = 0
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            do {
                let downloaded = try await Self.downloadPreview(from: sourceURL) { value in
                    progress = value
                }
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: downloaded)
                    return
                }
                preparePlayer(localURL: downloaded)
            } catch {
                if !Task.isCancelled {
                    errorMessage = L10n.detail.previewFailed
                    buffering = false
                    progress = 0
                }
            }
        }
    }

    private func preparePlayer(localURL url: URL) {
        removeObserver()
        if let localURL {
            try? FileManager.default.removeItem(at: localURL)
        }
        let nextPlayer = AVPlayer(url: url)
        nextPlayer.isMuted = true
        nextPlayer.actionAtItemEnd = .none
        if let item = nextPlayer.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak nextPlayer] _ in
                nextPlayer?.seek(to: .zero)
                nextPlayer?.play()
            }
        }
        localURL = url
        player = nextPlayer
        buffering = false
        progress = 1
        playing = true
        nextPlayer.play()
    }

    private func cleanup() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
        playing = false
        buffering = false
        progress = 0
        errorMessage = nil
        removeObserver()
        if let localURL {
            try? FileManager.default.removeItem(at: localURL)
            self.localURL = nil
        }
    }

    private func removeObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private static func downloadPreview(
        from url: URL,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        final class Holder: @unchecked Sendable { var observation: NSKeyValueObservation? }
        let holder = Holder()

        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
                holder.observation?.invalidate()
                holder.observation = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: URLError(.unknown))
                    return
                }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("wallxch-live-preview-\(UUID().uuidString).mp4")
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            holder.observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let fraction = progress.fractionCompleted
                guard fraction.isFinite else { return }
                Task { @MainActor in
                    onProgress(max(0, min(fraction, 1)))
                }
            }
            task.resume()
        }
    }
}

private struct InlineAVPlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> InlineAVPlayerNSView {
        InlineAVPlayerNSView()
    }

    func updateNSView(_ nsView: InlineAVPlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class InlineAVPlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

// Mock home/lock chrome painted over the hero in the matching mode.
struct HomeMockOverlay: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 22)
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(0..<6) { i in
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .opacity(Double(i + 1) / 7)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.12)))
            .padding(.bottom, 18)
        }
    }
}

struct LockMockOverlay: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 80)
            Text("9:41")
                .font(.system(size: 86, weight: .ultraLight))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 12)
            Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
