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

    var body: some View {
        // Anchor: an aspect-ratio Rectangle owns the cell size so the
        // LazyVGrid lays rows out correctly. The visual stack rides on
        // top via .overlay so it inherits that size without re-asking
        // SwiftUI to measure it (which was the source of the
        // overlap-between-rows bug — .aspectRatio on a ZStack
        // sometimes produced cells smaller than the column width).
        Rectangle()
            .fill(Color.clear)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    Color(hex: wallpaper.dominantColor ?? "#bbb").opacity(0.55)

                    CachedAsyncImage(url: URL(string: wallpaper.displayURL)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
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
                            if wallpaper.fileType.hasPrefix("video/") { videoChip }
                            if wallpaper.isDynamic                    { macChip }
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false)
                )
                // Soft shadow only — was 14/6 which visually bled
                // across the LazyVGrid's 12px gutter. Halving radius
                // keeps the lift but cleans up the row separation.
                .shadow(color: Color.black.opacity(hover ? 0.14 : 0.04), radius: hover ? 8 : 3, x: 0, y: hover ? 4 : 1)
            }
            .animation(.easeOut(duration: 0.18), value: hover)
            .onHover { entered in
                hover = entered
                if entered {
                    // Tell the page-mesh background to tint to this
                    // wallpaper's palette. The lighter list endpoints
                    // include color_palette now (comma-separated hex
                    // string) so the mesh can pull three distinct
                    // stops instead of degrading to dominant-only.
                    PaletteEnv.shared.apply(palette: wallpaper.colorPalette, dominant: wallpaper.dominantColor)
                } else {
                    PaletteEnv.shared.resetToDefaults()
                }
            }
            .contentShape(Rectangle())
    }

    // ─── Chips (match web .tile-chip family) ────────────────────

    private var resolutionChip: some View {
        Text(wallpaper.resolutionLabel)
            .font(.mono10).tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private var videoChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill").font(.system(size: 8))
            Text("VIDEO").font(.mono10).tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private var macChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "apple.logo").font(.system(size: 9, weight: .medium))
            Text("MAC").font(.mono10).tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private var aiChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles").font(.system(size: 9, weight: .medium))
            Text("AI").font(.mono10).tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color(red: 0.52, green: 0.20, blue: 0.78).opacity(0.92)))
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
