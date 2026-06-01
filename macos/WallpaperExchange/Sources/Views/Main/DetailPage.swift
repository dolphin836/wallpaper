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

    @State private var detail: WallpaperDetail?
    @State private var similar: [Wallpaper] = []
    @State private var loadError: String?
    @State private var mode: PreviewMode = .off
    @State private var manager = WallpaperManager.shared
    @State private var auth = AuthService.shared
    @State private var isLiked: Bool = false
    @State private var isFavorited: Bool = false
    @Environment(\.dismiss) private var dismiss

    enum PreviewMode: String { case off = "Wallpaper", plain = "Plain", home = "Home", lock = "Lock" }

    var body: some View {
        ZStack {
            backdrop
            ScrollView(.vertical, showsIndicators: false) {
                if let d = detail {
                    VStack(alignment: .leading, spacing: 24) {
                        breadcrumb(detail: d)
                        hero(detail: d)
                        actionBar(detail: d)
                        metaGrid(detail: d)
                        moreLikeThis
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 48).padding(.top, 12).padding(.bottom, 60)
                    .frame(maxWidth: 1100)
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

    private var backdrop: some View {
        ZStack {
            if let d = detail, let url = URL(string: d.displayURL) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 60).scaleEffect(1.2)
                } placeholder: {
                    Color(hex: d.dominantColor ?? "#bbb").opacity(0.4)
                }
            }
            Color.paper.opacity(0.78)
        }
        .ignoresSafeArea()
    }

    private func breadcrumb(detail: WallpaperDetail) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Kicker(text: "Specimen №\(detail.id)")
            Spacer()
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                    Text("ESC").font(.kicker).tracking(1.5)
                }
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.paper2))
                .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private func hero(detail: WallpaperDetail) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL(string: detail.displayURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: detail.dominantColor ?? "#bbb")
                }
                .frame(maxWidth: .infinity).frame(height: 440)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hair, lineWidth: 1))

                if mode == .home { HomeMockOverlay() }
                if mode == .lock { LockMockOverlay() }
            }
            .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.title.isEmpty ? "Wallpaper #\(detail.id)" : detail.title)
                        .font(.display24).foregroundStyle(Color.ink)
                    HStack(spacing: 8) {
                        Text("\(detail.width)×\(detail.height) px")
                        Text("·")
                        Text(detail.resolutionLabel)
                        Text("·")
                        Text(detail.fileType.uppercased())
                        if detail.isDynamic || detail.fileType.hasPrefix("video/") {
                            Text("·").padding(.leading, 2)
                            Text("LIVE").foregroundStyle(Color.accent)
                        }
                    }
                    .font(.mono11).tracking(0.5).foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private struct PreviewOption { let mode: PreviewMode; let icon: String }
    private static let previewOptions: [PreviewOption] = [
        .init(mode: .off,   icon: "rectangle.on.rectangle"),
        .init(mode: .plain, icon: "macbook"),
        .init(mode: .home,  icon: "rectangle.grid.2x2"),
        .init(mode: .lock,  icon: "clock"),
    ]

    private func actionBar(detail: WallpaperDetail) -> some View {
        HStack(spacing: 12) {
            actionPill(icon: isLiked ? "heart.fill" : "heart", label: isLiked ? "Liked" : "Like", count: "\(detail.likeCount)", on: isLiked) {
                Task { await toggleLike(detail) }
            }
            actionPill(icon: isFavorited ? "star.fill" : "star", label: isFavorited ? "Saved" : "Favorite", count: nil, on: isFavorited) {
                Task { await toggleFavorite(detail) }
            }
            divider
            HStack(spacing: 4) {
                ForEach(Self.previewOptions, id: \.mode.rawValue) { opt in
                    Button(action: { mode = opt.mode }) {
                        HStack(spacing: 5) {
                            Image(systemName: opt.icon).font(.system(size: 10, weight: .medium))
                            Text(opt.mode.rawValue).font(.sans11)
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
            divider
            Button(action: { Task { try? await manager.download(wallpaper: lightWallpaper(detail)) } }) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 11, weight: .medium))
                    Text("Save").font(.sans11)
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
                    Circle().fill(Color.accent).frame(width: 9, height: 9)
                    Text("Set on Mac · 1 coin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.paper)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.ink))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
        .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .center)
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
        .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .center)
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
        .frame(maxWidth: 880).frame(maxWidth: .infinity, alignment: .center)
    }

    // ─── Actions ────────────────────────────────────────────────
    private func load() async {
        loadError = nil
        do {
            let d = try await APIClient.shared.fetchWallpaperDetail(slug: slug)
            detail = d
            isLiked = d.isLiked ?? false
            isFavorited = d.isFavorited ?? false
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
