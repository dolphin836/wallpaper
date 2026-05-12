import SwiftUI

struct WallpaperRow: View {
    let wallpaper: Wallpaper
    let isLocal: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    let onDownloadAndSet: () -> Void
    let onSetWallpaper: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: URL(string: wallpaper.displayURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    placeholder
                }
            }
            .frame(height: 120)
            .clipped()

            // Top-left chips — always visible (matches web WallpaperCard).
            HStack(spacing: 4) {
                if !wallpaper.resolutionLabel.isEmpty {
                    chip(text: wallpaper.resolutionLabel)
                }
                if wallpaper.isDynamic {
                    chip(icon: "livephoto")
                }
            }
            .padding(8)

            // Bottom-right action stack — only on hover, hidden during download.
            if isHovering && !isDownloading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            if isLocal {
                                iconButton(icon: "desktopcomputer", help: "Set wallpaper", action: onSetWallpaper)
                            } else {
                                iconButton(icon: "arrow.down.circle", help: "Download", action: onDownload)
                                iconButton(icon: "desktopcomputer.and.arrow.down", help: "Download & set", action: onDownloadAndSet)
                            }
                        }
                    }
                }
                .padding(8)
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
