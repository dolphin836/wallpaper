import SwiftUI

// Single wallpaper card in the Discover grid. Three layers:
//   • image (16:9 hero, rounded, hover-lift)
//   • palette strip overlaid on the bottom edge — 5 colors at 6px tall
//   • metadata row below the image — title + resolution chip + dynamic flag
//
// Hover state lifts the card 4 px and reveals two quick-action chips
// on the image (Quick set + Save). Clicking opens the detail inspector
// (handled by the parent via onTapGesture).
struct WallpaperTile: View {
    let wallpaper: DemoWallpaper
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: wallpaper.previewURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(wallpaper.dominant.opacity(0.55))
                    }
                }
                .frame(height: 156)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Palette strip — 5 swatches stacked left-to-right on
                // the bottom edge. Reinforces the wallpaper's identity
                // and previews the page-tint the detail view will use.
                HStack(spacing: 0) {
                    ForEach(Array(wallpaper.palette.prefix(5).enumerated()), id: \.offset) { _, c in
                        Rectangle().fill(c)
                    }
                }
                .frame(height: 5)
                .clipShape(
                    .rect(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                )

                // Resolution chip — top-left corner.
                HStack(spacing: 4) {
                    Text(wallpaper.resolutionLabel)
                        .font(.dMono10)
                        .tracking(0.6)
                        .foregroundStyle(Color.dPaper)
                    if wallpaper.isDynamic {
                        Circle().fill(Color.dAccent).frame(width: 5, height: 5)
                        Text("DYN")
                            .font(.dMono10)
                            .tracking(0.8)
                            .foregroundStyle(Color.dAccent)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.dInk.opacity(0.55))
                )
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)

                // Hover overlay — Quick Set + Save chips. AppKit popup
                // would show these on right-click in the real app; here
                // they fade in on hover so the affordance is obvious.
                if isHovering {
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        HStack(spacing: 6) {
                            quickChip(icon: "rectangle.on.rectangle.angled", label: "Set on Mac")
                            quickChip(icon: "tray.and.arrow.down", label: "Save")
                            Spacer()
                            quickChip(icon: "ellipsis", label: "")
                        }
                    }
                    .padding(10)
                    .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.dHair, lineWidth: 1)
                    .allowsHitTesting(false)
            )

            // Metadata row. Tight 1-line title + small mono spec line
            // so the tile reads as a fact-card rather than just an image.
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.title)
                    .font(.dSans13)
                    .foregroundStyle(Color.dInk)
                    .lineLimit(1)
                Text("\(wallpaper.category.uppercased()) · @\(wallpaper.uploader)")
                    .font(.dMono10)
                    .tracking(0.6)
                    .foregroundStyle(Color.dMuted)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovering ? Color.dPaper : Color.clear)
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .shadow(color: Color.black.opacity(isHovering ? 0.10 : 0), radius: 12, x: 0, y: 6)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }

    private func quickChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            if !label.isEmpty {
                Text(label).font(.dSans11)
            }
        }
        .foregroundStyle(Color.dInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.dPaper.opacity(0.92))
        )
        .overlay(Capsule().stroke(Color.dHair, lineWidth: 0.5))
    }
}
