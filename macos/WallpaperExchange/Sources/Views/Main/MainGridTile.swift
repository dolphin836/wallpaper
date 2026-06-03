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
            // Fixed compact action-rail sizing — the same dot size on
            // every tile regardless of tile shape or full-screen state
            // (matching the windowed 16:10 Live tile, the shortest one).
            // A constant size avoids the dots looking bigger in
            // full-screen / on taller tiles.
            let railGap: CGFloat = 5
            let dotSize: CGFloat = 19
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

                // Action rail — web .tile-actions:
                //   position absolute, right: 10, bottom: 10
                //   flex-direction: column, gap: 6
                //   opacity 0 → 1 + translateY(4 → 0) on tile hover
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: railGap) {
                            ActionDot(icon: isFavorited ? "star.fill" : "star",
                                      kind: .favorite,
                                      active: isFavorited,
                                      help: isFavorited ? "Unfavorite" : "Favorite",
                                      busy: busy,
                                      size: dotSize,
                                      action: { Task { await toggleFavorite() } })
                            ActionDot(icon: isLiked ? "heart.fill" : "heart",
                                      kind: .like,
                                      active: isLiked,
                                      help: isLiked ? "Unlike" : "Like",
                                      busy: busy,
                                      size: dotSize,
                                      action: { Task { await toggleLike() } })
                            ActionDot(icon: isDownloaded ? "checkmark.circle.fill" : "tray.and.arrow.down",
                                      kind: .download,
                                      active: isDownloaded,
                                      help: isDownloaded ? "Downloaded" : "Download (1 coin)",
                                      busy: busy,
                                      size: dotSize,
                                      action: { Task { await doDownload() } })
                            ActionDot(icon: "rectangle.on.rectangle.angled",
                                      kind: .neutral,
                                      active: false,
                                      help: "Set as wallpaper",
                                      busy: busy,
                                      size: dotSize,
                                      action: { Task { await doSetWallpaper() } })
                        }
                        .opacity(hover ? 1 : 0)
                        .offset(y: hover ? 0 : 4)
                        .animation(.easeOut(duration: 0.2), value: hover)
                        .allowsHitTesting(hover)
                    }
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

    // ActionDot lives in this file (see bottom).

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

// ─── ActionDot — single hover-revealed action button ───────────
// Mirrors web .t-act:
//   34×34 circle, 1px white-22% border, rgba(15,12,8,0.45) bg
//   On hover: bg deepens to rgba(15,12,8,0.65)
//   Active states use color tokens (like #e0463a, fav #d8a23a, dl #4a8a5a)
struct ActionDot: View {
    enum Kind { case favorite, like, download, neutral }

    let icon: String
    let kind: Kind
    let active: Bool
    let help: String
    let busy: Bool
    // Diameter of the circle. Defaults to the web's 34pt, but the grid
    // shrinks it on short tiles (e.g. windowed 16:10 Live tiles) so the
    // 4-dot rail always fits without overflowing into the chips.
    var size: CGFloat = 34
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(bgColor)
                )
                .overlay(
                    Circle().stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(busy)
        .onHover { hover = $0 }
        .scaleEffect(hover && !active ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    // Web color tokens
    private var activeColor: Color {
        switch kind {
        case .favorite: return Color(red: 0.85, green: 0.64, blue: 0.23) // #d8a23a
        case .like:     return Color(red: 0.88, green: 0.27, blue: 0.23) // #e0463a
        case .download: return Color(red: 0.29, green: 0.54, blue: 0.35) // #4a8a5a
        case .neutral:  return Color.accent
        }
    }

    private var bgColor: Color {
        if active { return activeColor }
        // rgba(15,12,8, .45) at rest → .65 on hover
        let base = Color(red: 15.0/255, green: 12.0/255, blue: 8.0/255)
        return base.opacity(hover ? 0.78 : 0.55)
    }

    private var borderColor: Color {
        active ? .clear : Color.white.opacity(0.22)
    }
}
