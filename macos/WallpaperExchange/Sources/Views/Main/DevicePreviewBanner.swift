import SwiftUI
import AppKit

// Discover device preview — mirrors the web's device mockup: a monitor
// (bezel + stand) sitting on a soft glass card tinted by the featured
// wallpaper, with Plain / Home / Lock preview-mode pills underneath.
// The featured wallpaper updates as the user hovers grid tiles.
struct DevicePreviewBanner: View {
    let featured: Wallpaper?
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            DeviceMockup(wallpaper: featured)
        }
        .buttonStyle(.plain)
        .disabled(featured == nil)
        .frame(maxWidth: .infinity)
    }
}

// Web-parity monitor mockup. The screen wallpaper is cover-filled and
// hard-clipped to the screen rect, so a large image can never bleed
// past the bezel.
struct DeviceMockup: View {
    let wallpaper: Wallpaper?
    @State private var mode: Mode = .plain
    @State private var hover = false

    enum Mode: String, CaseIterable { case plain = "Plain", home = "Home", lock = "Lock" }

    private var deviceAspect: CGFloat {
        guard let s = NSScreen.main ?? NSScreen.screens.first, s.frame.height > 0 else { return 16.0 / 10.0 }
        return s.frame.width / s.frame.height
    }

    var body: some View {
        VStack(spacing: 18) {
            monitor
                .frame(maxWidth: 520)
                .scaleEffect(hover ? 1.005 : 1.0)
                .animation(.easeOut(duration: 0.2), value: hover)
                .onHover { hover = $0 }
            modeToggles
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(glassBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    // Monitor: bezel + clipped screen, then a stand neck + foot.
    private var monitor: some View {
        VStack(spacing: 0) {
            screen
                .aspectRatio(deviceAspect, contentMode: .fit)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)

            // Stand neck (trapezoid) + foot bar.
            Trapezoid()
                .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.30)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 86, height: 24)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.50), Color(white: 0.34)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 210, height: 9)
        }
    }

    // Thin, neutral charcoal bezel with concentric corners (outer 18 /
    // inner 12 with a 6pt frame), a faint glass edge highlight — closer
    // to the web's clean monitor.
    private var screen: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.17, blue: 0.19),
                                          Color(red: 0.11, green: 0.11, blue: 0.13)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                ZStack {
                    Color.black
                    if let wp = wallpaper {
                        CachedAsyncImage(url: URL(string: wp.displayURL)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(hex: wp.dominantColor ?? "#bbb").opacity(0.55)
                        }
                    } else {
                        Image(systemName: "rectangle.on.rectangle.angled").foregroundStyle(Color.muted)
                    }
                    if mode == .home { homeOverlay }
                    if mode == .lock { lockOverlay }
                }
                // Cover-fill is hard-clipped to the screen rect → no overflow.
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Plain / Home / Lock segmented pills.
    private var modeToggles: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases, id: \.self) { m in
                let on = mode == m
                Button { mode = m } label: {
                    Text(m.rawValue.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(on ? Color.paper : Color.ink2)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(on ? Color.ink : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.thinMaterial))
        .overlay(Capsule().strokeBorder(Color.hair, lineWidth: 1))
    }

    // Soft glass card tinted by a blurred copy of the featured wallpaper.
    private var glassBackground: some View {
        ZStack {
            if let wp = wallpaper {
                CachedAsyncImage(url: URL(string: wp.displayURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
                .blur(radius: 70)
                .opacity(0.38)
            }
            Rectangle().fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // Faint macOS home layer — menubar strip + a dock of coloured dots.
    private var homeOverlay: some View {
        VStack {
            Rectangle().fill(.ultraThinMaterial).frame(height: 14)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hue: Double(i) / 6.0, saturation: 0.55, brightness: 0.9))
                        .frame(width: 18, height: 18)
                }
            }
            .padding(6)
            .background(Capsule().fill(.ultraThinMaterial))
            .padding(.bottom, 8)
        }
    }

    // Lock layer — large clock + date over a dim scrim.
    private var lockOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 2) {
                Text(Self.clock).font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(Self.day).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .shadow(radius: 6)
            .padding(.top, 22)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private static var clock: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
    private static var day: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: Date())
    }
}

// Monitor stand neck — narrower at the top.
private struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        let inset = r.width * 0.30
        var p = Path()
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
