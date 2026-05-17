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

    // Constants for tile chrome. Single source so the chip and action-row
    // insets always agree no matter what's rendered above them.
    private let cornerRadius: CGFloat = 8
    private let chipInset: CGFloat = 8
    private let actionInset: CGFloat = 8

    private var thumbURL: URL? { wallpaper.thumbURL.isEmpty ? nil : URL(string: wallpaper.thumbURL) }
    private var previewURL: URL? { wallpaper.previewURL.isEmpty ? nil : URL(string: wallpaper.previewURL) }
    private var showActions: Bool { isHovering && !isDownloading }
    private var showLocalMissing: Bool { kind == .downloaded && !localFileExists }

    var body: some View {
        // Deterministic 16:10 frame. Putting aspectRatio directly on the
        // ZStack (rather than wrapping a GeometryReader) means every child
        // is laid out against the same fixed parent rect, so chip + action
        // insets land at identical screen coordinates on every tile.
        ZStack(alignment: .topLeading) {
            imageStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            hoverGradient

            // Top-left chips
            HStack(spacing: 5) {
                if !wallpaper.resolutionLabel.isEmpty {
                    Chip(text: wallpaper.resolutionLabel)
                }
                if wallpaper.isDynamic {
                    Chip(text: "Mac", icon: "apple.logo")
                }
            }
            .padding(chipInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Top-right state chip (Active / Local missing — mutually exclusive)
            HStack(spacing: 5) {
                if kind == .downloaded && isActive {
                    Chip(text: "Active", icon: "checkmark", tone: .active)
                } else if showLocalMissing {
                    Chip(text: "Local missing", icon: "lock", tone: .warn)
                }
            }
            .padding(chipInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Bottom-right hover actions
            HStack(spacing: 6) {
                switch kind {
                case .latest:
                    PillButton(icon: "arrow.down", label: "Download", primary: false, action: onDownload)
                    PillButton(icon: "display", label: "Set & download", primary: true, action: onDownloadAndSet)
                case .downloaded:
                    if !localFileExists {
                        PillButton(icon: "arrow.clockwise", label: "Re-download", primary: false, action: onRedownload)
                    }
                    PillButton(icon: "display", label: "Set as wallpaper", primary: true, action: onSetWallpaper)
                }
            }
            .padding(actionInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(showActions ? 1 : 0)
            .offset(y: showActions ? 0 : 6)
            .allowsHitTesting(showActions)

            if isDownloading { downloadingOverlay }
        }
        .aspectRatio(16.0/10.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.paper2)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.22), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isDownloading)
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
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .fixedSize()
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
            // Approximation of the design's rgba(255,255,255,0.18) glass
            // pill. Layered over the bottom-up dark gradient so it reads
            // as frosted glass against the image.
            Color.white.opacity(0.20)
        }
    }
}
