import SwiftUI
import AppKit

// Full-page wallpaper detail. Pushed onto the navigation stack from
// any wallpaper tile. Loads /wallpapers/:slug on appear to hydrate the
// richer WallpaperDetail (uploader / tags / palette) on top of the
// lighter Wallpaper carried by the list.
struct DetailPage: View {
    let slug: String
    var onUploader: (String) -> Void
    var onWallpaper: (Wallpaper) -> Void
    // Set when presented as a modal overlay — the breadcrumb close + ESC
    // dismiss the modal instead of popping the navigation stack.
    var onClose: (() -> Void)? = nil

    @State private var detail: WallpaperDetail?
    @State private var similar: [Wallpaper] = []
    @State private var loadError: String?
    @State private var mode: PreviewMode = .off
    @State private var manager = WallpaperManager.shared
    @State private var auth = AuthService.shared
    @State private var isLiked: Bool = false
    @State private var isFavorited: Bool = false
    @State private var myCollections: [CollectionBrief] = []
    @Environment(\.dismiss) private var dismiss

    enum PreviewMode: String { case off = "Wallpaper", plain = "Plain", home = "Home", lock = "Lock" }

    private struct DetailLayout {
        let size: CGSize
        let isModal: Bool

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

    var body: some View {
        GeometryReader { proxy in
            let layout = DetailLayout(size: proxy.size, isModal: onClose != nil)
            ZStack {
                backdrop(size: proxy.size)
                ScrollView(.vertical, showsIndicators: false) {
                    if let d = detail {
                        VStack(alignment: .leading, spacing: layout.isCompact ? 18 : 24) {
                            stagePanel(detail: d, layout: layout)
                            metaGrid(detail: d, layout: layout)
                            if !similar.isEmpty {
                                moreLikeThis(layout: layout)
                            }
                            Color.clear
                                .frame(height: 40)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.top, layout.topPadding)
                        .padding(.bottom, layout.bottomPadding)
                        .frame(width: layout.pageWidth, alignment: .leading)
                        // A vertical ScrollView otherwise lets a child's
                        // intrinsic width influence its horizontal origin.
                        .frame(width: layout.size.width, alignment: .center)
                    } else if let err = loadError {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(Color.warn)
                            Text(err).font(.sans12).foregroundStyle(Color.muted)
                            Button("Retry") { Task { await load() } }
                        }
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                    } else {
                        ProgressView()
                            .padding(.top, 80)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: "\(slug)-\(detail?.id ?? 0)-\(layout.recommendationLimit)") {
                await loadSimilar(limit: layout.recommendationLimit)
            }
        }
        .task(id: slug) { await load() }
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
            Kicker(text: "Specimen №\(detail.id)")
            Spacer()
        }
    }

    // Stage panel — a dominant-color gradient card holding the hero +
    // the toolbar (web .wd-panel).
    private func stagePanel(detail d: WallpaperDetail, layout: DetailLayout) -> some View {
        let tint = Color(hex: d.dominantColor ?? "#888")
        return VStack(spacing: layout.stageSpacing) {
            hero(detail: d, layout: layout)
            actionBar(detail: d, layout: layout)
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
            if mode == .off {
                rawHeroImage(detail: detail, layout: layout)
            } else {
                // Plain / Home / Lock → draw the actual device (monitor
                // bezel + stand) with the wallpaper on screen.
                DeviceMockup(wallpaper: lightWallpaper(detail), controlledMode: deviceMode, showChrome: false)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: layout.heroMaxHeight)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Raw wallpaper mirrors web .wd-hero-img: the image gets max-width /
    // max-height constraints, then the rounded border is attached to the
    // actual rendered image rect rather than a full-width SwiftUI frame.
    private func rawHeroImage(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        let size = rawHeroSize(detail: detail, layout: layout)
        return HStack {
            Spacer(minLength: 0)
            CachedAsyncImage(url: URL(string: detail.displayURL)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color(hex: detail.dominantColor ?? "#bbb")
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
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

    private func actionBar(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // File info (no title) + divider, then the action rows.
            metaRow(detail: detail)
            Rectangle().fill(Color.hair).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                actionRowsWide(detail: detail)
                actionRowsMedium(detail: detail)
                actionRowsCompact(detail: detail)
            }
        }
        .padding(layout.actionPadding)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.paper.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        .frame(maxWidth: .infinity)
    }

    private func actionRowsWide(detail: WallpaperDetail) -> some View {
        HStack(spacing: 12) {
            socialActions(detail: detail)
                .fixedSize(horizontal: true, vertical: false)
            divider
            previewModePicker
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 16)
            downloadActions(detail: detail)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func actionRowsMedium(detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                socialActions(detail: detail)
                    .fixedSize(horizontal: true, vertical: false)
                divider
                previewModePicker
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            downloadActions(detail: detail)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func actionRowsCompact(detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            socialActions(detail: detail)
            previewModePicker
            downloadActions(detail: detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func socialActions(detail: WallpaperDetail) -> some View {
        HStack(spacing: 6) {
            actionPill(icon: isLiked ? "heart.fill" : "heart", label: isLiked ? "Liked" : "Like", count: "\(detail.likeCount)", on: isLiked) {
                Task { await toggleLike(detail) }
            }
            actionPill(icon: isFavorited ? "star.fill" : "star", label: isFavorited ? "Saved" : "Favorite", count: nil, on: isFavorited) {
                Task { await toggleFavorite(detail) }
            }
            addToListMenu(detail)
        }
    }

    private var previewModePicker: some View {
        HStack(spacing: 4) {
            ForEach(Self.previewOptions, id: \.rawValue) { opt in
                Button(action: { mode = opt }) {
                    Text(opt.rawValue)
                        .font(.sans11)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(mode == opt ? Color.ink : Color.muted)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(Capsule().fill(mode == opt ? Color.paper : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.paper2))
        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
    }

    private func downloadActions(detail: WallpaperDetail) -> some View {
        let downloading = manager.downloading.contains(detail.id)
        let progress = manager.downloadProgress[detail.id]
        return HStack(spacing: 6) {
            Button(action: { Task { try? await manager.download(wallpaper: lightWallpaper(detail)) } }) {
                downloadLabel(icon: "tray.and.arrow.down",
                              text: progressText(defaultText: "Download", progress: progress),
                              emphasized: false)
            }
            .disabled(downloading)
            .buttonStyle(.plain)
            Button(action: {
                Task {
                    try? await manager.download(wallpaper: lightWallpaper(detail))
                    try? await manager.setAsWallpaper(lightWallpaper(detail))
                }
            }) {
                downloadLabel(icon: "arrow.down.circle.fill",
                              text: progressText(defaultText: "Download & set · 1 coin", progress: progress),
                              emphasized: true)
            }
            .disabled(downloading)
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
        }
    }

    private func progressText(defaultText: String, progress: Double?) -> String {
        guard let progress else { return defaultText }
        return "\(Int(progress * 100))%"
    }

    private func downloadLabel(icon: String, text: String, emphasized: Bool) -> some View {
        HStack(spacing: emphasized ? 7 : 6) {
            Image(systemName: icon).font(.system(size: emphasized ? 12 : 11, weight: emphasized ? .semibold : .medium))
            Text(text)
                .font(.system(size: emphasized ? 12 : 11, weight: emphasized ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(emphasized ? Color.white : Color.ink2)
        .padding(.horizontal, emphasized ? 16 : 11).padding(.vertical, emphasized ? 8 : 6)
        .background(Capsule().fill(emphasized ? Color.accent : Color.paper))
        .overlay(Capsule().stroke(emphasized ? Color.clear : Color.hair, lineWidth: 1))
        .shadow(color: emphasized ? Color.accent.opacity(0.45) : Color.clear, radius: emphasized ? 10 : 0, y: emphasized ? 4 : 0)
    }

    // File info row inside the toolbar (web .wd-actionbar-meta): big
    // dimensions + mono "res · TYPE · size", plus LIVE / AI pills.
    private func metaRow(detail d: WallpaperDetail) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metaDimensions(detail: d)
                metaSpecs(detail: d)
                metaBadges(detail: d)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    metaDimensions(detail: d)
                    metaBadges(detail: d)
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
        Text("\(d.resolutionLabel) · \(d.fileType.uppercased()) · \(byteString(d.fileSize))")
            .font(.system(size: 11, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(Color.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func metaBadges(detail d: WallpaperDetail) -> some View {
        if d.isDynamic || d.fileType.hasPrefix("video/") {
            Text("● LIVE").font(.system(size: 9, design: .monospaced)).tracking(1.4)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.ink))
        }
        if d.isAIGenerated == true {
            Text("✦ AI").font(.system(size: 9, design: .monospaced)).tracking(1.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color(red: 0.42, green: 0.28, blue: 0.7)))
        }
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
                    Text(c).font(.mono10).tracking(0.4).foregroundStyle(Color.muted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.paper2))
                }
            }
            .foregroundStyle(on ? Color.accent : Color.ink2)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(Color.paper))
            .overlay(Capsule().stroke(on ? Color.accent : Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Color.hair).frame(width: 1, height: 22)
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.hair, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statsStrip(detail: WallpaperDetail, layout: DetailLayout) -> some View {
        if layout.isCompact {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                statCell(label: "DOWNLOADS", value: "\(detail.downloadCount)")
                statCell(label: "LIKES", value: "\(detail.likeCount)")
                statCell(label: "FAVORITED", value: "\(detail.favoriteCount)")
                statCell(label: "VIEWS", value: "\(detail.viewCount)")
            }
            .padding(.horizontal, 4).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
        } else {
            HStack(spacing: 0) {
                statCell(label: "DOWNLOADS", value: "\(detail.downloadCount)")
                divider
                statCell(label: "LIKES", value: "\(detail.likeCount)")
                divider
                statCell(label: "FAVORITED", value: "\(detail.favoriteCount)")
                divider
                statCell(label: "VIEWS", value: "\(detail.viewCount)")
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
            Kicker(text: "Uploaded by")
            if let u = detail.uploader {
                Button(action: { onUploader(u.username) }) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.paper2).frame(width: 40, height: 40)
                            .overlay(Text(String((u.nickname?.isEmpty == false ? u.nickname! : u.username).prefix(1)).uppercased()).font(.displayLg).foregroundStyle(Color.ink))
                            .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(u.username)").font(.sans13).foregroundStyle(Color.ink)
                            Text("VIEW PROFILE →").font(.kicker).tracking(2).foregroundStyle(Color.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Unknown").font(.sans13).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aboutCell(detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: "About")
            Text("Wallpaper")
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
            Kicker(text: pal.isEmpty ? "Palette" : "Palette · \(pal.count) colors")
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
                    Text("DOMINANT · \(dc.uppercased())")
                        .font(.kicker).tracking(2).foregroundStyle(Color.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moreLikeThis(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("More like this · \(similar.count)")
                    .font(.displayLg).foregroundStyle(Color.ink)
                Spacer()
                Rectangle().fill(Color.hair).frame(height: 1)
            }
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
    private func load() async {
        loadError = nil
        do {
            let d = try await APIClient.shared.fetchWallpaperDetail(slug: slug)
            detail = d
            isLiked = d.isLiked ?? false
            isFavorited = d.isFavorited ?? false
            await loadCollections(wallpaperID: d.id)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadSimilar(limit: Int) async {
        guard let detail else { return }
        if let wallpapers = try? await APIClient.shared.fetchSimilarWallpapers(wallpaperID: detail.id, limit: limit) {
            similar = wallpapers
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

    // Reconstruct a lightweight Wallpaper from a WallpaperDetail so we
    // can hand it to WallpaperManager (which expects the popover shape).
    // "Add to list" — a menu of the user's collections (checkmark on the
    // ones already containing this wallpaper). Mirrors the web's
    // AddToCollectionModal entry point.
    private func addToListMenu(_ detail: WallpaperDetail) -> some View {
        Menu {
            if myCollections.isEmpty {
                Text("No collections yet")
            } else {
                ForEach(myCollections) { c in
                    Button {
                        Task {
                            try? await APIClient.shared.addToCollection(collectionID: c.id, wallpaperID: detail.id)
                            await loadCollections(wallpaperID: detail.id)
                        }
                    } label: {
                        if c.containsWallpaper == true {
                            Label(c.title, systemImage: "checkmark")
                        } else {
                            Text(c.title)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                Text("Add to list").font(.sans11)
            }
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(Color.paper))
            .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
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
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.55))
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
