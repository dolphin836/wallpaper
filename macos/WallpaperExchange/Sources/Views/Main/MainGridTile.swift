import SwiftUI

// Wallpaper grid card — matches web salon tiles. Image fills a 3:2
// frame on the dominant-color floor; chips overlay top-left
// (Resolution / Video / Mac / AI); hover reveals a 4-button action
// rail at top-right (Favorite · Like · Download · Set as wallpaper).
struct MainGridTile: View {
    let wallpaper: Wallpaper
    var aspectRatio: CGFloat = 3.0 / 2.0
    @State private var hover = false
    @State private var manager = WallpaperManager.shared
    @State private var auth = AuthService.shared

    // Local mirror state — optimistically toggles for snappy hover
    // feedback. We don't have a re-fetch on success here; the detail
    // page does the authoritative state.
    @State private var liked: Bool? = nil
    @State private var favorited: Bool? = nil
    @State private var downloaded: Bool? = nil
    @State private var busy: Bool = false

    private var isLiked: Bool { liked ?? (wallpaper.isLiked ?? false) }
    private var isFavorited: Bool { favorited ?? (wallpaper.isFavorited ?? false) }
    private var isDownloaded: Bool { downloaded ?? (wallpaper.isDownloaded ?? false) }

    // GeometryReader-anchored sizing — proven reliable in
    // MacDynamicTile after Rectangle/.aspectRatio variants leaked the
    // underlying image's intrinsic aspect through portrait wallpapers.
    // proxy.size.width comes from the LazyVGrid cell's proposed width;
    // we compute height = width / aspectRatio and pin the ZStack to
    // exactly that. The outer .aspectRatio modifier tells the grid the
    // row height to reserve. Every cell in a row ends up the same size
    // regardless of the source image's orientation.
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.width / aspectRatio
            ZStack {
                Color(hex: wallpaper.dominantColor ?? "#bbb").opacity(0.55)

                CachedAsyncImage(url: URL(string: wallpaper.displayURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(width: proxy.size.width, height: h)
                .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.20), .clear, .clear, Color.black.opacity(0.30)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(hover ? 1 : 0.65)
                .allowsHitTesting(false)

                VStack {
                    HStack(alignment: .top, spacing: 4) {
                        resolutionChip
                        if wallpaper.fileType.hasPrefix("video/") || wallpaper.isDynamic { liveChip }
                        if wallpaper.isAIGenerated == true        { aiChip }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        if hover {
                            HStack(spacing: 6) {
                                actionDot(icon: isFavorited ? "star.fill" : "star",
                                          active: isFavorited,
                                          help: isFavorited ? "Unfavorite" : "Favorite") { Task { await toggleFavorite() } }
                                actionDot(icon: isLiked ? "heart.fill" : "heart",
                                          active: isLiked,
                                          help: isLiked ? "Unlike" : "Like") { Task { await toggleLike() } }
                                actionDot(icon: isDownloaded ? "checkmark.circle.fill" : "tray.and.arrow.down",
                                          active: isDownloaded,
                                          help: isDownloaded ? "Downloaded" : "Download (1 coin)") { Task { await doDownload() } }
                                actionDot(icon: "rectangle.on.rectangle.angled",
                                          active: false,
                                          help: "Set as wallpaper") { Task { await doSetWallpaper() } }
                            }
                            .transition(.opacity)
                        }
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(width: proxy.size.width, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(hover ? 0.14 : 0.04), radius: hover ? 8 : 3, x: 0, y: hover ? 4 : 1)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .animation(.easeOut(duration: 0.18), value: hover)
        .onHover { entered in
            hover = entered
            if entered {
                PaletteEnv.shared.apply(palette: wallpaper.colorPalette, dominant: wallpaper.dominantColor)
            } else {
                PaletteEnv.shared.resetToDefaults()
            }
        }
        .contentShape(Rectangle())
    }

    // ─── Chips (match web .tile-chip family) ────────────────────
    //   padding: 2px 7px
    //   font: mono 9px / weight 600 / letter-spacing 0.04em
    //   background: light translucent (oklch(98% 0.005 240 / 0.62))
    //   color: dark slate (oklch(34% 0.012 240))
    //   AI variant: violet wash with white text

    private static let chipBG    = Color.white.opacity(0.78)
    private static let chipInk   = Color(red: 0.20, green: 0.21, blue: 0.23)
    private static let chipFont  = Font.system(size: 9, weight: .semibold, design: .monospaced)

    private var resolutionChip: some View {
        Text(wallpaper.resolutionLabel)
            .font(Self.chipFont).tracking(0.4)
            .foregroundStyle(Self.chipInk)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Self.chipBG))
    }

    private var liveChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill").font(.system(size: 8, weight: .semibold))
            Text("LIVE").font(Self.chipFont).tracking(0.4)
        }
        .foregroundStyle(Self.chipInk)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Self.chipBG))
    }

    private var aiChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .semibold))
            Text("AI").font(Self.chipFont).tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        // .is-ai: oklch(70% 0.18 295 / 0.85) — violet wash
        .background(Capsule().fill(Color(red: 0.62, green: 0.30, blue: 0.82).opacity(0.85)))
    }

    // ─── Action rail dot ──────────────────────────────────────

    private func actionDot(icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? Color.accent : Color.paper)
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? Color.ink : Color.ink.opacity(0.72)))
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(busy)
    }

    // ─── Action handlers ──────────────────────────────────────

    private func toggleLike() async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isLiked
        liked = !prev
        do {
            if prev { try await APIClient.shared.unlike(wallpaperID: wallpaper.id) }
            else    { try await APIClient.shared.like(wallpaperID: wallpaper.id) }
        } catch { liked = prev }
    }
    private func toggleFavorite() async {
        guard auth.isLoggedIn else { auth.login(); return }
        let prev = isFavorited
        favorited = !prev
        do {
            if prev { try await APIClient.shared.unfavorite(wallpaperID: wallpaper.id) }
            else    { try await APIClient.shared.favorite(wallpaperID: wallpaper.id) }
        } catch { favorited = prev }
    }
    private func doDownload() async {
        guard auth.isLoggedIn else { auth.login(); return }
        busy = true; defer { busy = false }
        do {
            try await manager.download(wallpaper: wallpaper)
            downloaded = true
            await auth.refreshProfile()
        } catch {}
    }
    private func doSetWallpaper() async {
        guard auth.isLoggedIn else { auth.login(); return }
        busy = true; defer { busy = false }
        do {
            try await manager.download(wallpaper: wallpaper)
            downloaded = true
            try await manager.setAsWallpaper(wallpaper)
            await auth.refreshProfile()
        } catch {}
    }
}
