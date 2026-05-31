import SwiftUI

// Wallpaper card for the main-window grids. Differs from the popover's
// WallpaperTileView in that it shows a 16:9 hero, palette strip on the
// bottom edge, and hover-revealed Quick Set / Save chips. Used by the
// Discover / Downloads / Liked / Profile / Collection grids.
struct MainGridTile: View {
    let wallpaper: Wallpaper
    @State private var hover = false
    @State private var manager = WallpaperManager.shared

    private var palette: [String] {
        // The lightweight Wallpaper model doesn't carry the full
        // color_palette string — fall back to a single-color "palette"
        // built from dominant_color so the bottom edge isn't empty.
        if let dc = wallpaper.dominantColor, !dc.isEmpty { return [dc] }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: URL(string: wallpaper.displayURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: wallpaper.dominantColor ?? "#bbb").opacity(0.55)
                }
                .frame(height: 156)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Palette strip / dominant color bottom edge.
                if !palette.isEmpty {
                    VStack {
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(palette, id: \.self) { hex in
                                Rectangle().fill(Color(hex: hex))
                            }
                        }
                        .frame(height: 5)
                        .clipShape(
                            .rect(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                        )
                    }
                    .allowsHitTesting(false)
                }

                // Resolution chip.
                HStack(spacing: 4) {
                    Text(wallpaper.resolutionLabel)
                        .font(.mono10).tracking(0.6)
                        .foregroundStyle(Color.paper)
                    if wallpaper.isDynamic {
                        Circle().fill(Color.accent).frame(width: 5, height: 5)
                        Text("DYN")
                            .font(.mono10).tracking(0.8)
                            .foregroundStyle(Color.accent)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.ink.opacity(0.55)))
                .padding(10)
                .allowsHitTesting(false)

                if hover {
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        HStack(spacing: 6) {
                            actionChip(icon: "rectangle.on.rectangle.angled", label: "Set on Mac") {
                                Task { try? await manager.download(wallpaper: wallpaper); try? await manager.setAsWallpaper(wallpaper) }
                            }
                            actionChip(icon: "tray.and.arrow.down", label: "Save") {
                                Task { try? await manager.download(wallpaper: wallpaper) }
                            }
                            Spacer()
                        }
                    }
                    .padding(10)
                    .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.title.isEmpty ? "Wallpaper #\(wallpaper.id)" : wallpaper.title)
                    .font(.sans13).foregroundStyle(Color.ink).lineLimit(1)
                Text(metaLine)
                    .font(.mono10).tracking(0.6)
                    .foregroundStyle(Color.muted).lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(hover ? Color.paper : Color.clear)
        )
        .scaleEffect(hover ? 1.01 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.10 : 0), radius: 12, x: 0, y: 6)
        .animation(.easeOut(duration: 0.18), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    private var metaLine: String {
        let res = "\(wallpaper.width)×\(wallpaper.height)"
        return "\(wallpaper.resolutionLabel.uppercased()) · \(res)"
    }

    private func actionChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(label).font(.sans11)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.paper.opacity(0.92)))
            .overlay(Capsule().stroke(Color.hair, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
