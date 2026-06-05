import SwiftUI
import AppKit

// Simplified discover device preview. The web mounts a floating wall
// (DeviceFloatingWall) animating wallpapers around a device chassis;
// here we render a single static MacBook chassis at the top of
// Discover with the first matched / featured wallpaper rendered
// inside its screen + a small caption pulling the user's display
// metrics. Clicking the chassis opens that wallpaper's detail.
struct DevicePreviewBanner: View {
    let featured: Wallpaper?
    var onPick: () -> Void

    private var screenSize: (width: Int, height: Int) {
        let scr = NSScreen.main ?? NSScreen.screens.first!
        let dpr = Int(scr.backingScaleFactor)
        return (Int(scr.frame.width) * dpr, Int(scr.frame.height) * dpr)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            // Left rail — kicker + caption about the device.
            VStack(alignment: .leading, spacing: 8) {
                Kicker(text: "Tailored for your screen")
                Text("Your Mac · \(screenSize.width)×\(screenSize.height)")
                    .font(.display24).foregroundStyle(Color.ink)
                Text("Wallpapers below ship variants sized for this display. Hover any tile for one-click set.")
                    .font(.sans13).foregroundStyle(Color.muted)
                    .frame(maxWidth: 360, alignment: .leading)
            }

            Spacer()

            // Right — MacBook chassis with featured wallpaper inside.
            Button(action: onPick) {
                MacBookOutlinePreview(wallpaper: featured)
                    .frame(width: 360, height: 230)
            }
            .buttonStyle(.plain)
            .disabled(featured == nil)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.paper.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.hair, lineWidth: 1)
        )
    }
}

// Lightweight MacBook chassis — bezel + screen + base bar. Wallpaper
// fills the screen rect. Not a full DeviceMockup — just enough chrome
// for the banner to read as "your laptop".
struct MacBookOutlinePreview: View {
    let wallpaper: Wallpaper?
    @State private var hover = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let bezel: CGFloat = 8
            let baseH: CGFloat = 10
            let screenH = h - baseH - 4
            VStack(spacing: 4) {
                // Screen
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                    if let wp = wallpaper {
                        CachedAsyncImage(url: URL(string: wp.displayURL)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(hex: wp.dominantColor ?? "#bbb").opacity(0.55)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(bezel)
                    } else {
                        Image(systemName: "rectangle.dashed")
                            .foregroundStyle(Color.muted)
                    }
                    // Camera dot in the top bezel
                    Circle().fill(Color(red: 0.04, green: 0.04, blue: 0.05))
                        .frame(width: 3, height: 3)
                        .offset(y: -screenH / 2 + bezel / 2)
                }
                .frame(height: screenH)
                // Clip the whole screen so a large (cover-filled) wallpaper
                // can never bleed past the device's screen rect.
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Base bar with notch.
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.78, green: 0.78, blue: 0.80))
                    Capsule().fill(Color(red: 0.58, green: 0.58, blue: 0.60))
                        .frame(width: w * 0.18, height: 3)
                        .offset(y: -1)
                }
                .frame(width: w + 16, height: baseH)
                .padding(.horizontal, -8)
            }
            .scaleEffect(hover ? 1.01 : 1.0)
            .shadow(color: Color.black.opacity(hover ? 0.22 : 0.12), radius: hover ? 18 : 10, x: 0, y: hover ? 10 : 6)
            .animation(.easeOut(duration: 0.2), value: hover)
            .onHover { hover = $0 }
        }
    }
}
