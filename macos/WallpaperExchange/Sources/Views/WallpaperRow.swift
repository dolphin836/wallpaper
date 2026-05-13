import SwiftUI

enum WallpaperRowColumn {
    case latest      // Discover list — hover reveals Download / Download & Set
    case downloaded  // Local-only list — hover reveals Set Wallpaper
}

struct WallpaperRow: View {
    let wallpaper: Wallpaper
    let column: WallpaperRowColumn
    let isDownloading: Bool
    let onDownload: () -> Void
    let onDownloadAndSet: () -> Void
    let onSetWallpaper: () -> Void

    @State private var isHovering = false
    @State private var highResLoaded = false

    private var thumbURL: URL? {
        wallpaper.thumbURL.isEmpty ? nil : URL(string: wallpaper.thumbURL)
    }
    private var previewURL: URL? {
        wallpaper.previewURL.isEmpty ? nil : URL(string: wallpaper.previewURL)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bottom layer: low-res thumb. Slightly blurred until the preview
            // covers it, so the upscaled 400×300 doesn't look pixelated. Falls
            // back to the dominant-color placeholder if no thumb URL.
            CachedAsyncImage(url: thumbURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
            .frame(height: 120)
            .clipped()
            .blur(radius: highResLoaded ? 0 : 6)
            .animation(.easeInOut(duration: 0.25), value: highResLoaded)

            // Top layer: 1600px preview. Same image source the detail page
            // uses — loading it here populates the browser cache (well, our
            // ImageCacheStore + URLCache) so detail navigation is instant.
            // Fades in over the blurred thumb once decoded.
            if previewURL != nil {
                CachedAsyncImage(
                    url: previewURL,
                    onLoad: { highResLoaded = true }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(height: 120)
                .clipped()
                .opacity(highResLoaded ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: highResLoaded)
            }

            // Top-left chips — always visible (matches web WallpaperCard).
            // The outer .frame ensures this attaches to the topLeading corner of the
            // image rather than collapsing to content size and floating mid-row.
            HStack(spacing: 4) {
                if !wallpaper.resolutionLabel.isEmpty {
                    chip(text: wallpaper.resolutionLabel)
                }
                if wallpaper.isDynamic {
                    chip(icon: "livephoto")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Bottom-right action stack — always rendered, toggled via opacity +
            // hit-testing. Conditionally rendering this on `isHovering` caused the
            // SwiftUI hover-flicker bug on macOS: mounting the buttons triggered the
            // parent's .onHover to fire `false` (mouse "enters" newly-inserted child),
            // which unmounted them, which re-fired `true`, looping at ~60Hz so the
            // buttons appeared to vanish under the cursor. Always-rendered avoids the
            // mount/unmount cycle entirely; .animation on the ZStack root still gives
            // a smooth fade.
            let showButtons = isHovering && !isDownloading
            VStack(spacing: 6) {
                switch column {
                case .latest:
                    iconButton(icon: "arrow.down.circle", help: "Download", action: onDownload)
                    iconButton(icon: "desktopcomputer.and.arrow.down", help: "Download & set", action: onDownloadAndSet)
                case .downloaded:
                    iconButton(icon: "desktopcomputer", help: "Set wallpaper", action: onSetWallpaper)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(showButtons ? 1 : 0)
            .allowsHitTesting(showButtons)

            // Downloading state — full dim + spinner, takes precedence over hover overlay.
            if isDownloading {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text("Downloading…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        // Make the entire 120px rectangle hit-testable, including transparent
        // areas. Without this, SwiftUI's default hover hit-test on a ZStack only
        // counts the visible content (the image + chips + buttons). When the
        // cursor crossed into a row's "empty" pixels — exactly where the buttons
        // fade in — the hover-deepest-hit chain could re-evaluate and bounce
        // hover state between this row and its neighbour, producing the
        // "approach button on row 1, it disappears, row 2's button shows up"
        // pattern reported by the user.
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.15), value: isDownloading)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(hex: wallpaper.dominantColor ?? "#e5e7eb"))
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }

    // Compact pill (text or icon) used for the top-left badges.
    private func chip(text: String? = nil, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            if let text {
                Text(text)
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // Circular icon button used in the bottom-right hover stack.
    private func iconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0.9; g = 0.9; b = 0.9
        }
        self.init(red: r, green: g, blue: b)
    }
}
