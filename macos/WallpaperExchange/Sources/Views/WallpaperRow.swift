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

            // Bottom-right action stack — only on hover, hidden during download.
            // Without an explicit `maxWidth/maxHeight: .infinity` here, the inner
            // Spacers have no room to push and the stack collapses to its content
            // size, leaving the buttons pinned to the topLeading corner of the
            // ZStack alongside the chips.
            if isHovering && !isDownloading {
                VStack(spacing: 6) {
                    // The button set is driven by the *column* the row appears in, not by
                    // whether the file happens to be on disk. A wallpaper showing up in
                    // Latest after a previous download still offers download — the user can
                    // re-download, or just hover-click to see what they get.
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
                .transition(.opacity)
            }

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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
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
