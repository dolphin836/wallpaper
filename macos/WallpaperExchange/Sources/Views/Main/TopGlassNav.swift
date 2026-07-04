import SwiftUI
import AppKit

// Shared liquid-glass capsule chrome.
//
// On macOS 26+ this uses the real Liquid Glass material introduced at
// WWDC25 (.glassEffect) — the system material brings edge lensing,
// dynamic highlights, automatic legibility adaptation over bright/dark
// backdrops, and accessibility integration (Reduced Transparency /
// Increased Contrast) for free. Per the design guidance the bar is ONE
// glass surface; the controls inside use plain tint highlights instead
// of nested glass (no glass-on-glass stacking).
//
// Below macOS 26 it falls back to the hand-rolled approximation
// (ultraThinMaterial + paper tint + gradient hairline + shadow).
struct GlassPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            // GlassEffectContainer is required whenever more than one
            // glass surface renders together (the bar + the selection
            // droplet riding on it): glass cannot sample other glass,
            // so the container gives them one shared sampling region
            // and lets nearby shapes blend/morph like liquid instead
            // of stacking with artifacts.
            //
            // .interactive() adds the under-surface illumination
            // feedback when the user clicks controls on the glass.
            // The extra drop shadow lifts the bar off the backdrop —
            // bigger elements cast deeper shadows per the material's
            // scaling rules, and the default one is too faint over
            // busy wallpaper imagery.
            GlassEffectContainer(spacing: 20) {
                row
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .overlay(GlassLightingOverlay(intensity: 0.8))
            }
            // Two shadows: a tight contact shadow and a wide ambient
            // one. Splitting them is what makes the bar read as
            // floating at a definite height instead of just "blurry".
            .shadow(color: Color.black.opacity(0.18), radius: 3, y: 2)
            .shadow(color: Color.black.opacity(0.20), radius: 22, y: 10)
        } else {
            row
                .background(.ultraThinMaterial, in: Capsule())
                .background(
                    // Soft paper tint under the material so the glass
                    // stays legible over bright and dark backdrops.
                    Capsule().fill(Color.paper.opacity(0.28))
                )
                .overlay(GlassLightingOverlay(intensity: 0.9))
                .shadow(color: Color.black.opacity(0.18), radius: 3, y: 2)
                .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
        }
    }

    private var row: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(5)
    }
}

// Hand-drawn light passes layered over the glass, modelled on the
// passes aave.com describes in "Building Glass for the Web": a 45°
// specular sheen where light enters the lens, a bright top rim with a
// dark counter-rim underneath (reads as physical thickness), and a
// whisper of chromatic fringe hugging opposite edges. The native
// glassEffect supplies refraction; these passes supply the sculpted
// light that makes the surface read as a solid object.
struct GlassLightingOverlay: View {
    // Droplets are small lenses and take stronger light than the bar.
    var intensity: Double = 1.0

    var body: some View {
        ZStack {
            // Specular sheen — light entering from the top-leading
            // corner at ~45°, fading out before the midline.
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.26 * intensity), location: 0),
                            .init(color: .white.opacity(0.05 * intensity), location: 0.34),
                            .init(color: .clear, location: 0.58),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            // Rim light along the top edge…
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.60 * intensity), location: 0),
                            .init(color: .white.opacity(0.10 * intensity), location: 0.42),
                            .init(color: .clear, location: 0.78),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)

            // …and a dark counter-rim at the bottom edge, which is
            // what sells the pane as having thickness.
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15 * intensity)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            // Chromatic fringe: a cool hairline biased to the
            // top-leading edge and a warm one to the bottom-trailing,
            // like dispersion at the lens rim.
            Capsule()
                .strokeBorder(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.10 * intensity), lineWidth: 0.5)
                .offset(x: -0.4, y: -0.4)
                .blendMode(.plusLighter)
            Capsule()
                .strokeBorder(Color(red: 1.0, green: 0.62, blue: 0.45).opacity(0.10 * intensity), lineWidth: 0.5)
                .offset(x: 0.4, y: 0.4)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

// Press feedback for controls sitting on glass: a quick squish with a
// springy release, so clicks feel like pressing into the material
// rather than a flat state swap.
struct GlassBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// Hairline separator between groups inside a GlassPill.
struct GlassPillDivider: View {
    var body: some View {
        Capsule()
            .fill(Color.ink.opacity(0.16))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

// Small dark capsule label shown under chrome buttons on hover — same
// treatment the old collapsed sidebar used for its fly-out labels.
struct HoverTip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 15.0 / 255, green: 12.0 / 255, blue: 8.0 / 255).opacity(0.92)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.22), radius: 6, y: 2)
            .allowsHitTesting(false)
            .transition(.opacity)
            .zIndex(10)
    }
}

// The single liquid-glass chrome bar fixed at the window's top-centre.
// Two groups separated by a hairline divider:
//   1. Navigation — icon + label segments for the browse destinations
//      (with the liquid selection droplet).
//   2. Identity — the avatar chip (account/settings, or sign-in).
struct GlassChromeBar: View {
    let selection: MainWindow.SidebarItem?
    let onSelect: (MainWindow.SidebarItem) -> Void
    let avatarActive: Bool
    let onAvatar: () -> Void

    // Shared geometry space for the selection droplet, so it slides
    // and stretches between nav segments like a bead of water instead
    // of blinking from one to the other.
    @Namespace private var dropletNS

    private static let navItems: [MainWindow.SidebarItem] = [.home, .discover, .weekly, .collections]

    var body: some View {
        GlassPill {
            ForEach(Self.navItems, id: \.self) { item in
                GlassNavItem(
                    item: item,
                    isSelected: item == selection,
                    dropletNamespace: dropletNS,
                    action: { onSelect(item) }
                )
            }

            GlassPillDivider()

            ToolbarAvatarButton(active: avatarActive, action: onAvatar)
        }
        // Drives the droplet's matched-geometry slide. The low damping
        // gives the overshoot-and-settle wobble that makes it read as
        // liquid rather than a sliding rectangle.
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: selection)
    }
}

private struct GlassNavItem: View {
    let item: MainWindow.SidebarItem
    let isSelected: Bool
    let dropletNamespace: Namespace.ID
    let action: () -> Void

    @State private var hover = false

    private var fg: Color {
        if isSelected { return Color.ink }
        return hover ? Color.ink : Color.ink2
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Text(item.label)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 17)
            .frame(height: 34)
            .background {
                if isSelected {
                    selectionDroplet
                        .matchedGeometryEffect(id: "chrome-nav-droplet", in: dropletNamespace)
                } else if hover {
                    Capsule().fill(Color.ink.opacity(0.08))
                }
            }
            .scaleEffect(hover && !isSelected ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .focusEffectDisabled()
        .focusable(false)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: hover)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    // The selected segment is itself a small Liquid Glass lens riding
    // on the bar — a raised droplet with real edge refraction on
    // macOS 26, approximated with a highlight-edged capsule on older
    // systems. Both variants carry a contact shadow for lift.
    //
    // glassEffectID ties the droplet into the chrome bar's
    // GlassEffectContainer: when the selection moves, the glass system
    // morphs the lens between segments (stretch-and-settle) instead of
    // fading it out and in — matchedGeometryEffect at the call site
    // carries the tint layer along the same path.
    @ViewBuilder
    private var selectionDroplet: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.paper.opacity(0.30))
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("chrome-nav-droplet-glass", in: dropletNamespace)
                // Small lenses take the strongest light of the family —
                // the sheen + rim pair is what makes the droplet look
                // convex instead of flat.
                .overlay(GlassLightingOverlay(intensity: 1.5))
                .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
        } else {
            Capsule()
                .fill(Color.paper.opacity(0.92))
                .overlay(GlassLightingOverlay(intensity: 1.3))
                .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
        }
    }
}

// Avatar chip inside the toolbar pill. Signed-in shows the user's
// avatar (initial fallback); signed-out shows a person glyph and
// starts the login flow on click.
struct ToolbarAvatarButton: View {
    var active: Bool = false
    let action: () -> Void

    @State private var auth = AuthService.shared
    @State private var hover = false

    private let size: CGFloat = 30

    var body: some View {
        Button(action: action) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                // Always-on ring so the avatar reads as a control even
                // at rest: a crisp white ring with a dark outer hair
                // for separation on bright backdrops. Accent when the
                // account page is open.
                .overlay(
                    Circle().strokeBorder(
                        active ? Color.accent.opacity(0.85) : Color.white.opacity(hover ? 0.95 : 0.75),
                        lineWidth: 1.5
                    )
                )
                .background(
                    Circle()
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                        .padding(-0.5)
                )
                .frame(width: 34, height: 34)
                .scaleEffect(hover ? 1.12 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .focusEffectDisabled()
        .focusable(false)
        .overlay(alignment: .top) {
            if hover {
                HoverTip(text: auth.isLoggedIn ? L10n.shell.settings : L10n.shell.signIn)
                    .offset(y: 42)
            }
        }
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: hover)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let u = auth.user {
            if !u.avatarURL.isEmpty, let url = URL(string: u.avatarURL) {
                CachedAsyncImage(url: url, maxPixelDimension: 96) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialBadge(for: u)
                }
            } else {
                initialBadge(for: u)
            }
        } else {
            ZStack {
                Circle().fill(Color.paper2)
                Image(systemName: "person")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func initialBadge(for user: User) -> some View {
        ZStack {
            Circle().fill(Color.paper2)
            Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink)
        }
    }
}
