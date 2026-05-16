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

    private var thumbURL: URL? { wallpaper.thumbURL.isEmpty ? nil : URL(string: wallpaper.thumbURL) }
    private var previewURL: URL? { wallpaper.previewURL.isEmpty ? nil : URL(string: wallpaper.previewURL) }
    private var showActions: Bool { isHovering && !isDownloading }
    private var showLocalMissing: Bool { kind == .downloaded && !localFileExists }

    var body: some View {
        GeometryReader { geo in
            // 16:10 tile per the hand-off.
            let h = geo.size.width * 10.0 / 16.0
            ZStack {
                imageStack
                hoverGradient
                chipsLayer
                if isDownloading { downloadingOverlay }
                actionsLayer
            }
            .frame(width: geo.size.width, height: h)
            .background(Color.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.22), value: isHovering)
            .animation(.easeInOut(duration: 0.15), value: isDownloading)
        }
        // Reserve vertical space matching the 16:10 aspect so GeometryReader
        // doesn't end up zero-sized inside a VStack.
        .aspectRatio(16.0/10.0, contentMode: .fit)
    }

    // ─── Layers ───────────────────────────────────────────────────

    @ViewBuilder private var imageStack: some View {
        // Slight scale-up + brightness bump on hover, lifted from the
        // web salon tile but at a gentler 600ms ease.
        let img = ZStack {
            CachedAsyncImage(url: thumbURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholderFill
            }
            .blur(radius: previewLoaded ? 0 : 6)

            if previewURL != nil {
                CachedAsyncImage(url: previewURL, onLoad: { previewLoaded = true }) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
                .opacity(previewLoaded ? 1 : 0)
            }
        }
        img
            .scaleEffect(isHovering ? 1.035 : 1.0)
            .brightness(isHovering ? 0.04 : 0)
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: isHovering)
            .clipped()
    }

    private var placeholderFill: some View {
        Rectangle().fill(Color(hex: wallpaper.dominantColor ?? "#e5e7eb"))
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

    private var chipsLayer: some View {
        VStack {
            HStack {
                HStack(spacing: 5) {
                    if !wallpaper.resolutionLabel.isEmpty {
                        Chip(text: wallpaper.resolutionLabel)
                    }
                    if wallpaper.isDynamic {
                        Chip(text: "Mac", icon: "apple.logo")
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    if kind == .downloaded && isActive {
                        Chip(text: "Active", icon: "checkmark", tone: .active)
                    } else if showLocalMissing {
                        Chip(text: "Local missing", icon: "lock", tone: .warn)
                    }
                }
            }
            .padding(9)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var actionsLayer: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    switch kind {
                    case .latest:
                        PillButton(icon: "arrow.down", label: "Download", primary: false, action: onDownload)
                        PillButton(icon: "arrow.down.to.line", label: "Set & download", primary: true, action: onDownloadAndSet)
                    case .downloaded:
                        if !localFileExists {
                            PillButton(icon: "arrow.clockwise", label: "Re-download", primary: false, action: onRedownload)
                        }
                        PillButton(icon: "display", label: "Set as wallpaper", primary: true, action: onSetWallpaper)
                    }
                }
            }
            .padding(10)
        }
        .opacity(showActions ? 1 : 0)
        .offset(y: showActions ? 0 : 6)
        .allowsHitTesting(showActions)
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
    enum Tone { case neutral, active, warn }
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
    }

    @ViewBuilder private var background: some View {
        switch tone {
        case .neutral: Color.black.opacity(0.55)
        case .active:  Color.accent
        case .warn:    Color.warn
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
                    .font(.sans11)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(background)
            .overlay(
                Capsule().stroke(primary ? Color.clear : Color.white.opacity(0.28), lineWidth: 1)
            )
            .clipShape(Capsule())
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { _ in } // suppress default plain-button hover noise
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
            // Approximation of the design's `rgba(255,255,255,0.18)` glass
            // pill with backdrop-filter blur. Layering a translucent white
            // over a Material gives a similar frosted look against the
            // hover gradient.
            ZStack {
                Color.white.opacity(0.18)
            }
        }
    }
}
