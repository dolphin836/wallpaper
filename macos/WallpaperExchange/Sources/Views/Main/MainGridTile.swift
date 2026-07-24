import SwiftUI
import AppKit

// Wallpaper grid card — matches web salon tiles. Image fills a 3:2
// frame on the dominant-color floor; chips overlay top-left
// (Resolution / Video / Mac / AI); hover reveals a 3-button action
// rail at top-right (Favorite · Like · Download). Setting a wallpaper
// now lives in DetailPage so users can choose the target display.
struct MainGridTile: View {
    let wallpaper: Wallpaper
    var aspectRatio: CGFloat = 3.0 / 2.0
    // When true (the My Downloads grid), show a chip on tiles whose
    // file is no longer in the local downloads folder (e.g. cleared).
    var flagIfNotLocal: Bool = false
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
    @State private var transferAction: TransferAction? = nil

    private var isLiked: Bool { liked ?? (wallpaper.isLiked ?? false) }
    private var isFavorited: Bool { favorited ?? (wallpaper.isFavorited ?? false) }
    private var localFileExists: Bool { manager.isDownloaded(wallpaper.id) }
    private var isOwnWallpaper: Bool { auth.user?.id == wallpaper.userID }
    private var isDownloaded: Bool {
        if let downloaded { return downloaded }
        if flagIfNotLocal { return localFileExists }
        return wallpaper.isDownloaded ?? localFileExists
    }
    private var downloadHelp: String {
        if isDownloaded { return L10n.browse.tipGotIt }
        if flagIfNotLocal || isOwnWallpaper { return L10n.browse.tipDownload }
        return L10n.browse.tipTradeForOne
    }
    private var isTransferring: Bool { manager.downloading.contains(wallpaper.id) }
    private var downloadProgress: Double? { manager.downloadProgress[wallpaper.id] }
    private var downloadButtonLoading: Bool { isTransferring && (transferAction == .download || transferAction == nil) }

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
            let dotSize: CGFloat = 22
            ZStack {
                Color(hex: wallpaper.dominantColor ?? "#bbb").opacity(0.55)

                ProgressiveCachedAsyncImage(
                    lowURL: URL(string: wallpaper.thumbURL),
                    highURL: URL(string: wallpaper.previewURL),
                    lowMaxPixelDimension: 520,
                    highMaxPixelDimension: 1100
                ) { img in
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
                        if wallpaper.isDynamic && !wallpaper.fileType.hasPrefix("video/") { macChip }
                        if wallpaper.isAIGenerated == true        { aiChip }
                        if flagIfNotLocal && !localFileExists { notLocalChip }
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
                            ActionDot(icon: .system(isFavorited ? "star.fill" : "star"),
                                      kind: .favorite,
                                      active: isFavorited,
                                      help: isFavorited ? L10n.browse.tipUnfavorite : L10n.browse.tipFavorite,
                                      busy: busy,
                                      size: dotSize,
                                      action: { Task { await toggleFavorite() } })
                            ActionDot(icon: .system(isLiked ? "heart.fill" : "heart"),
                                      kind: .like,
                                      active: isLiked,
                                      help: isLiked ? L10n.browse.tipUnlike : L10n.browse.tipLike,
                                      busy: busy,
                                      size: dotSize,
                                      action: { Task { await toggleLike() } })
                            ActionDot(icon: isDownloaded ? .system("checkmark.circle") : .webDownload,
                                      kind: .download,
                                      active: isDownloaded,
                                      help: downloadHelp,
                                      busy: busy,
                                      loading: downloadButtonLoading,
                                      progress: downloadProgress,
                                      size: dotSize,
                                      action: { Task { await doDownload() } })
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
    // Resolution and live-media tags use the shared Web-matched component;
    // AI and local-file state retain their existing semantic treatments.
    private static let chipInk   = Color.chipInk
    private static let chipFont  = Font.system(size: 9, weight: .semibold, design: .monospaced)

    private var resolutionChip: some View {
        WallpaperCardTag(wallpaper.resolutionLabel, kind: .resolution)
    }

    private var liveChip: some View {
        WallpaperCardTag(L10n.browse.chipLive, kind: .live, icon: "play.fill")
    }

    private var macChip: some View {
        WallpaperCardTag("Mac", kind: .mac, icon: "desktopcomputer")
    }

    // Local-file-missing tag for the My Downloads grid — amber wash so
    // it reads as a gentle "not on this Mac" status rather than an error.
    private var notLocalChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "externaldrive.badge.xmark").font(.system(size: 8, weight: .semibold))
            Text(L10n.browse.chipMissing).font(Self.chipFont).tracking(0.4)
        }
        .foregroundStyle(Self.chipInk)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Color.chipMissing.opacity(0.95)))
    }

    private var aiChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .semibold))
            Text("AI").font(Self.chipFont).tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        // .is-ai: oklch(70% 0.18 295 / 0.85) — violet wash
        .background(Capsule().fill(Color.chipAI.opacity(0.85)))
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
        if localFileExists { return }
        busy = true; transferAction = .download
        defer { busy = false; transferAction = nil }
        do {
            try await manager.download(wallpaper: wallpaper)
            downloaded = true
            await auth.refreshProfile()
        } catch {}
    }
}

private enum TransferAction {
    case download
}

// ─── ActionDot — single hover-revealed action button ───────────
// Mirrors web .t-act:
//   34×34 circle, 1px white-22% border, rgba(15,12,8,0.45) bg
//   On hover: bg deepens to rgba(15,12,8,0.65)
//   Active states use color tokens (like #e0463a, fav #d8a23a, dl #4a8a5a)
struct ActionDot: View {
    enum Kind { case favorite, like, download, neutral }
    enum Icon {
        case system(String)
        case webDownload
    }

    let icon: Icon
    let kind: Kind
    let active: Bool
    let help: String
    let busy: Bool
    var loading: Bool = false
    var progress: Double? = nil
    // Diameter of the circle. Defaults to the web's 34pt, but the grid
    // shrinks it on short tiles (e.g. windowed 16:10 Live tiles) so the
    // 4-dot rail always fits without overflowing into the chips.
    var size: CGFloat = 34
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(bgColor)
                Group {
                    switch icon {
                    case .system(let systemName):
                        Image(systemName: systemName)
                    case .webDownload:
                        WebDownloadIconShape()
                    }
                }
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size * 0.42, height: size * 0.42)
                Circle().stroke(borderColor, lineWidth: 1)
                if loading {
                    progressRing
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(busy || loading)
        .onHover { hovering in
            hover = hovering
            // Pointing-hand cursor on hover so the dots read as
            // clickable. push/pop pairs the enter/exit events.
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .scaleEffect(hover && !active ? 1.03 : 1.0)
        // Hover label, pinned to the LEFT of the dot (the rail hugs the
        // tile's right edge). Anchoring to the dot's trailing edge and
        // adding trailing padding of (dot width + gap) pushes the whole
        // capsule clear of the dot's left edge with an 8pt gap —
        // reliable regardless of the label's width.
        .overlay(alignment: .trailing) {
            if hover {
                tooltip
                    .padding(.trailing, size + 8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: loadingProgress)
    }

    private var tooltip: some View {
        Text(help)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.tipSurface.opacity(0.92)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // Web color tokens
    private var activeColor: Color {
        switch kind {
        case .favorite: return Color.stateFavorite
        case .like:     return Color.stateLike
        case .download: return Color.stateDownloaded
        case .neutral:  return Color.accent
        }
    }

    private var bgColor: Color {
        if active { return activeColor }
        // rgba(15,12,8, .45) at rest → .65 on hover
        let base = Color.tipSurface
        return base.opacity(hover ? 0.78 : 0.55)
    }

    private var borderColor: Color {
        if loading { return Color.accent.opacity(0.34) }
        if active { return .clear }
        // Brighten the ring on hover for a clear affordance.
        return Color.white.opacity(hover ? 0.6 : 0.22)
    }

    private var loadingProgress: Double {
        guard loading else { return 0 }
        return min(max(progress ?? 0.08, 0.08), 1)
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.accent.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: loadingProgress)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1)
        .allowsHitTesting(false)
    }
}
