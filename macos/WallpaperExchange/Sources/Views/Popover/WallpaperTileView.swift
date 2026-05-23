import SwiftUI

// What hover action set to render. Two parallel surfaces share the same
// tile chrome but expose different actions:
//   .latest      — Download / Set & download
//   .downloaded  — Set as wallpaper (plus optional Re-download when the
//                  local file is missing)
enum WallpaperTileKind {
    case latest
    case downloaded
}

struct WallpaperTileView: View {
    let wallpaper: Wallpaper
    let kind: WallpaperTileKind
    let isDownloading: Bool
    let downloadProgress: Double?
    // .downloaded only: when false, surface a "Local missing" chip and a
    // Re-download action. Ignored for .latest.
    let localFileExists: Bool
    // .downloaded only: highlight the currently-applied wallpaper. The
    // chip is mutually exclusive with the "Local missing" chip — by
    // construction, an Active wallpaper has its file on disk.
    let isActive: Bool
    let onDownload: () -> Void
    let onDownloadAndSet: () -> Void
    let onSetWallpaper: () -> Void
    let onRedownload: () -> Void

    @State private var isHovering = false
    @State private var previewLoaded = false

    // Constants for tile chrome. 12px on every side per user spec.
    private let cornerRadius: CGFloat = 8
    private let chipInset: CGFloat = 12
    private let actionInset: CGFloat = 12

    private var thumbURL: URL? { wallpaper.thumbURL.isEmpty ? nil : URL(string: wallpaper.thumbURL) }
    private var previewURL: URL? { wallpaper.previewURL.isEmpty ? nil : URL(string: wallpaper.previewURL) }
    private var showActions: Bool { isHovering && !isDownloading }
    private var showLocalMissing: Bool { kind == .downloaded && !localFileExists }

    var body: some View {
        // Color.clear + aspectRatio is the canonical SwiftUI scaffold for
        // "fixed-aspect container that flexes with the parent's width."
        // Each .overlay(alignment:) call attaches a layer at one of the
        // four corners — far more predictable than .frame(maxWidth:
        // maxHeight: alignment:), which mixes padding with stretch+align
        // and was producing the "some tiles' chips drift above the top
        // edge" symptom on certain renders.
        Color.clear
            .aspectRatio(16.0/10.0, contentMode: .fit)
            .overlay { imageStack.clipped() }
            .overlay { hoverGradient }
            .overlay(alignment: .topLeading) { topLeftChips }
            .overlay(alignment: .topTrailing) { topRightChip }
            .overlay(alignment: .bottomTrailing) { actionRow }
            .overlay { downloadingOverlayIfActive }
            .background(Color.paper2)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            // contentShape on a Rectangle (not the rounded one) makes the
            // *entire* 16:10 bounding rect hit-testable for hover, including
            // the four corner triangles that the rounded-rect shape excludes.
            // That was the source of "hover unreliably doesn't fire on some
            // tiles" — the cursor entered through a corner that
            // RoundedRectangle considered outside its hit region.
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.22), value: isHovering)
            .animation(.easeInOut(duration: 0.15), value: isDownloading)
    }

    // ─── Corner layers ───────────────────────────────────────────

    @ViewBuilder private var topLeftChips: some View {
        HStack(spacing: 5) {
            // Always rendered now — Wallpaper.resolutionLabel falls back
            // to "{w}×{h}" or "HD" when the backend hasn't backfilled
            // dimensions, so the slot is never empty.
            Chip(text: wallpaper.resolutionLabel)
            if wallpaper.isDynamic {
                Chip(text: "Mac", icon: "apple.logo")
            }
            if wallpaper.isAIGenerated == true {
                Chip(text: "AI", icon: "sparkles", tone: .ai)
            }
        }
        .padding(chipInset)
    }

    @ViewBuilder private var topRightChip: some View {
        if kind == .downloaded && isActive {
            Chip(text: "Active", icon: "checkmark", tone: .active)
                .padding(chipInset)
        } else if showLocalMissing {
            Chip(text: "Local missing", icon: "lock", tone: .warn)
                .padding(chipInset)
        }
    }

    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 6) {
            switch kind {
            case .latest:
                // If the file is already on this Mac (the user already paid
                // and pulled it on this device), the Download / Set &
                // download pair are both confusing — "download" implies the
                // file isn't local, but it is. Collapse to a single Set as
                // wallpaper button, matching .downloaded's hover row.
                if localFileExists {
                    PillButton(icon: "display", label: "Set as wallpaper", primary: true, action: onSetWallpaper)
                } else {
                    PillButton(icon: "arrow.down", label: "Download", primary: false, action: onDownload)
                    PillButton(icon: "display", label: "Set & download", primary: true, action: onDownloadAndSet)
                }
            case .downloaded:
                if !localFileExists {
                    PillButton(icon: "arrow.clockwise", label: "Re-download", primary: false, action: onRedownload)
                }
                PillButton(icon: "display", label: "Set as wallpaper", primary: true, action: onSetWallpaper)
            }
        }
        .padding(actionInset)
        .opacity(showActions ? 1 : 0)
        .offset(y: showActions ? 0 : 6)
        .allowsHitTesting(showActions)
    }

    @ViewBuilder private var downloadingOverlayIfActive: some View {
        if isDownloading { downloadingOverlay }
    }

    // ─── Layers ───────────────────────────────────────────────────

    @ViewBuilder private var imageStack: some View {
        ZStack {
            CachedAsyncImage(url: thumbURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color(hex: wallpaper.dominantColor ?? "#e5e7eb"))
            }
            .blur(radius: previewLoaded ? 0 : 6)

            if previewURL != nil {
                CachedAsyncImage(url: previewURL, onLoad: { previewLoaded = true }) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
                .opacity(previewLoaded ? 1 : 0)
            }
        }
        // Force imageStack to take the overlay-proposed size rather than
        // collapsing to the image's natural dimensions, which is what made
        // a single tile occasionally render at the image's intrinsic ratio
        // (chip then "drifts above" the visible rect because the rect is
        // shorter than the surrounding tile-frame would imply).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(isHovering ? 1.035 : 1.0)
        .brightness(isHovering ? 0.04 : 0)
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: isHovering)
    }

    private var hoverGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.78), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .opacity(showActions ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var downloadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(spacing: 8) {
                if let p = downloadProgress, p > 0 {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(maxWidth: 200)
                    Text("\(Int(p * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Downloading…")
                        .font(.sans11)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Sub-components

private struct Chip: View {
    enum Tone { case neutral, active, warn, ai }
    let text: String
    var icon: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .fixedSize()
    }

    // Per the design spec the neutral chip wants `rgba(0,0,0,0.55)` over a
    // `backdrop-filter: blur(8px)`. The pure-black-at-55% approximation
    // disappeared on bright images (cloudy skies, beaches) — chips looked
    // "missing." Stacking a thin Material under the dark tint adds the
    // backdrop blur the design called for, so the chip stays legible
    // against any image without lifting the tint above the spec.
    @ViewBuilder private var background: some View {
        switch tone {
        case .neutral:
            ZStack {
                Rectangle().fill(.thinMaterial)
                Color.black.opacity(0.45)
            }
            .environment(\.colorScheme, .dark)
        case .active:
            Color.accent
        case .warn:
            Color.warn
        case .ai:
            // Matches the web's `bg-violet-600/85` AI badge so the chip
            // reads as "this came out of cmd/aigen" across surfaces.
            Color(red: 0.45, green: 0.30, blue: 0.85).opacity(0.85)
        }
    }
}

private struct PillButton: View {
    let icon: String
    let label: String
    let primary: Bool
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(background)
            .overlay(
                Capsule().stroke(primary ? Color.clear : Color.white.opacity(0.28), lineWidth: 1)
            )
            .clipShape(Capsule())
            .fixedSize()
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    @ViewBuilder private var background: some View {
        if primary {
            Color.accent
        } else {
            // Design's rgba(255,255,255,0.18) glass pill. Layered over the
            // bottom-up dark gradient so it reads as frosted glass against
            // the image.
            Color.white.opacity(0.18)
        }
    }
}
