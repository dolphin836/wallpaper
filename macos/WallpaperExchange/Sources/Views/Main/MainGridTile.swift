import SwiftUI

// Wallpaper card for main-window grids — visually matches the web's
// salon WallpaperCard. Image fills a 3:2 frame on the dominant-color
// backdrop, the resolution / dynamic / AI chips sit absolute top-left,
// hover reveals the favorite / like / download action rail on the
// top-right. No separate metadata strip — title only on detail page.
struct MainGridTile: View {
    let wallpaper: Wallpaper
    var aspectRatio: CGFloat = 3.0 / 2.0
    @State private var hover = false
    @State private var manager = WallpaperManager.shared

    var body: some View {
        ZStack {
            // Dominant color floor.
            Color(hex: wallpaper.dominantColor ?? "#bbb")
                .opacity(0.55)

            // Image fills frame.
            CachedAsyncImage(url: URL(string: wallpaper.displayURL)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .clipped()

            // Bottom darken gradient — kicks up under chip / hover ink.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.28),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(hover ? 1 : 0.7)

            // Top-left chips.
            VStack {
                HStack(alignment: .top, spacing: 4) {
                    chip(text: wallpaper.resolutionLabel)
                    if wallpaper.fileType.hasPrefix("video/") { chip(text: "VIDEO") }
                    if wallpaper.isDynamic { chip(text: "MAC", accent: true) }
                    if wallpaper.isAIGenerated == true { chip(text: "AI", aiStyle: true) }
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
            .allowsHitTesting(false)

            // Top-right hover action rail — favorite / like / set on Mac.
            VStack {
                HStack {
                    Spacer()
                    if hover {
                        HStack(spacing: 6) {
                            actionDot(icon: "star") { /* favorite stub */ }
                            actionDot(icon: "heart") { /* like stub */ }
                            actionDot(icon: "rectangle.on.rectangle.angled") {
                                Task {
                                    try? await manager.download(wallpaper: wallpaper)
                                    try? await manager.setAsWallpaper(wallpaper)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                Spacer()
            }
            .padding(10)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false)
        )
        .scaleEffect(hover ? 1.015 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.18 : 0.06), radius: hover ? 16 : 8, x: 0, y: hover ? 8 : 4)
        .animation(.easeOut(duration: 0.18), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    private func chip(text: String, accent: Bool = false, aiStyle: Bool = false) -> some View {
        Text(text)
            .font(.mono10).tracking(0.6)
            .foregroundStyle(aiStyle ? Color.white : (accent ? Color.accent : Color.paper))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                Capsule().fill(
                    aiStyle ? Color(red: 0.52, green: 0.20, blue: 0.78).opacity(0.9)
                    : Color.ink.opacity(0.55)
                )
            )
    }

    private func actionDot(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.paper)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.ink.opacity(0.72)))
        }
        .buttonStyle(.plain)
    }
}
