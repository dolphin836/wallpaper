import SwiftUI

struct WallpaperRow: View {
    let wallpaper: Wallpaper
    let isLocal: Bool
    let onDownload: () -> Void
    let onSetWallpaper: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
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

            if isHovering {
                overlay
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(hex: wallpaper.dominantColor ?? "#e5e7eb"))
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }

    private var overlay: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 4) {
                Spacer()
                HStack(spacing: 4) {
                    Text(wallpaper.title.isEmpty ? "Untitled" : wallpaper.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !wallpaper.resolutionLabel.isEmpty {
                        Text(wallpaper.resolutionLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if wallpaper.isDynamic {
                        Image(systemName: "livephoto")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()
                }

                HStack(spacing: 6) {
                    if isLocal {
                        actionButton("Set Wallpaper", icon: "desktopcomputer") {
                            onSetWallpaper()
                        }
                    } else {
                        actionButton("Download", icon: "arrow.down.circle") {
                            onDownload()
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
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
