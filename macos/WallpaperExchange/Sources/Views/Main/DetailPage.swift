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

    private var deviceMode: DeviceMockup.Mode {
        switch mode {
        case .home: .home
        case .lock: .lock
        default: .plain
        }
    }

    var body: some View {
        ZStack {
            backdrop
            ScrollView(.vertical, showsIndicators: false) {
                if let d = detail {
                    VStack(alignment: .leading, spacing: 24) {
                        stagePanel(detail: d)
                        metaGrid(detail: d)
                        moreLikeThis
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 32).padding(.top, 16).padding(.bottom, 60)
                    // Content width to match the other pages.
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if let err = loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(Color.warn)
                        Text(err).font(.sans12).foregroundStyle(Color.muted)
                        Button("Retry") { Task { await load() } }
                    }
                    .padding(.top, 80)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
        }
        .task(id: slug) { await load() }
    }

    // Full-bleed blurred preview of the wallpaper itself behind the
    // whole panel (web .wd-backdrop: blur 38 / saturate 1.4 / scale 1.18)
    // with a soft paper scrim on top so content stays legible.
    private var backdrop: some View {
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
    }

    private func breadcrumb(detail: WallpaperDetail) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Kicker(text: "Specimen №\(detail.id)")
            Spacer()
        }
    }

    // Stage panel — a dominant-color gradient card holding the hero +
    // the toolbar (web .wd-panel).
    private func stagePanel(detail d: WallpaperDetail) -> some View {
        let tint = Color(hex: d.dominantColor ?? "#888")
        return VStack(spacing: 16) {
            hero(detail: d)
            actionBar(detail: d)
        }
        .padding(20)
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

    private func hero(detail: WallpaperDetail) -> some View {
        Group {
            if mode == .off {
                // Raw wallpaper filling the card width (web wd-hero-img:
                // width 100%, height auto). Height follows the decoded
                // image's real aspect, so it never leaves side gaps and
                // never crops — regardless of the stored width/height.
                CachedAsyncImage(url: URL(string: detail.displayURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color(hex: detail.dominantColor ?? "#bbb")
                        .aspectRatio(CGFloat(max(detail.width, 1)) / CGFloat(max(detail.height, 1)), contentMode: .fit)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
            } else {
                // Plain / Home / Lock → draw the actual device (monitor
                // bezel + stand) with the wallpaper on screen.
                DeviceMockup(wallpaper: lightWallpaper(detail), controlledMode: deviceMode, showChrome: false)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct PreviewOption { let mode: PreviewMode; let icon: String }
    private static let previewOptions: [PreviewOption] = [
        .init(mode: .off,   icon: "rectangle.on.rectangle"),
        .init(mode: .plain, icon: "macbook"),
        .init(mode: .home,  icon: "rectangle.grid.2x2"),
        .init(mode: .lock,  icon: "clock"),
    ]

    private func actionBar(detail: WallpaperDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // File info (no title) + divider, then the action rows.
            metaRow(detail: detail)
            Rectangle().fill(Color.hair).frame(height: 1)
            HStack(spacing: 12) {
            actionPill(icon: isLiked ? "heart.fill" : "heart", label: isLiked ? "Liked" : "Like", count: "\(detail.likeCount)", on: isLiked) {
                Task { await toggleLike(detail) }
            }
            actionPill(icon: isFavorited ? "star.fill" : "star", label: isFavorited ? "Saved" : "Favorite", count: nil, on: isFavorited) {
                Task { await toggleFavorite(detail) }
            }
            addToListMenu(detail)
            divider
            HStack(spacing: 4) {
                ForEach(Self.previewOptions, id: \.mode.rawValue) { opt in
                    Button(action: { mode = opt.mode }) {
                        HStack(spacing: 5) {
                            Image(systemName: opt.icon).font(.system(size: 10, weight: .medium))
                            Text(opt.mode.rawValue).font(.sans11).lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(mode == opt.mode ? Color.ink : Color.muted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(mode == opt.mode ? Color.paper : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.paper2))
            .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
            Spacer(minLength: 16)
            Button(action: { Task { try? await manager.download(wallpaper: lightWallpaper(detail)) } }) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 11, weight: .medium))
                    Text("Download").font(.sans11)
                }
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(Color.paper))
                .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: {
                Task {
                    try? await manager.download(wallpaper: lightWallpaper(detail))
                    try? await manager.setAsWallpaper(lightWallpaper(detail))
                }
            }) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 12, weight: .semibold))
                    Text("Download & set · 1 coin")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Color.accent))
                .shadow(color: Color.accent.opacity(0.45), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.paper.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        .frame(maxWidth: .infinity)
    }

    // File info row inside the toolbar (web .wd-actionbar-meta): big
    // dimensions + mono "res · TYPE · size", plus LIVE / AI pills.
    private func metaRow(detail d: WallpaperDetail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(d.width.formatted()) × \(d.height.formatted())")
                .font(.system(size: 15, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
            Text("\(d.resolutionLabel) · \(d.fileType.uppercased()) · \(byteString(d.fileSize))")
                .font(.system(size: 11, design: .monospaced)).tracking(0.4).foregroundStyle(Color.muted)
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
            Spacer(minLength: 0)
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

    private func metaGrid(detail: WallpaperDetail) -> some View {
        VStack(spacing: 0) {
            statsStrip(detail: detail)
            HStack(alignment: .top, spacing: 24) {
                uploaderCell(detail: detail)
                aboutCell(detail: detail)
                paletteCell(detail: detail)
            }
            .padding(20)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.hair, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private func statsStrip(detail: WallpaperDetail) -> some View {
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

    private var moreLikeThis: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("More like this · \(similar.count)")
                    .font(.displayLg).foregroundStyle(Color.ink)
                Spacer()
                Rectangle().fill(Color.hair).frame(height: 1)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(similar) { wp in
                    Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp) }
                        .buttonStyle(.plain)
                }
            }
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
            if let s = try? await APIClient.shared.fetchSimilarWallpapers(wallpaperID: d.id, limit: 12) {
                similar = s
            }
        } catch {
            loadError = error.localizedDescription
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
