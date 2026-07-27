import SwiftUI
import AppKit

// The window's top chrome, assembled from GlassKit primitives:
//   • GlassChromeBar — nav segments (liquid selection droplet) +
//     divider + avatar chip, in one GlassPill.
//   • GlassBackButton — floating circle for pushed pages (⌘[).

struct GlassChromeBar: View {
    let selection: MainWindow.SidebarItem?
    let onSelect: (MainWindow.SidebarItem) -> Void
    let avatarActive: Bool
    let onAvatar: () -> Void

    // Shared geometry space for the selection droplet, so it slides
    // and stretches between nav segments like a bead of water.
    @Namespace private var dropletNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let navItems: [MainWindow.SidebarItem] = [.home, .discover, .weekly, .collections]

    var body: some View {
        GlassPill {
            ForEach(Self.navItems, id: \.self) { item in
                GlassSegmentItem(
                    segment: GlassSegment(id: item, label: item.label, icon: item.icon),
                    isSelected: item == selection,
                    dropletNamespace: dropletNS,
                    action: { onSelect(item) }
                )
            }

            GlassPillDivider()

            ToolbarAvatarButton(active: avatarActive, action: onAvatar)
        }
        // Keep this frequently-used navigation transition quick and
        // disable its movement when Reduce Motion is enabled.
        .animation(reduceMotion ? nil : GlassMotion.selection, value: selection)
    }
}

// Floating circular back button for pushed second-level pages — the
// nav pill itself has no room for history controls, so this sits on
// the chrome row's free left side, next to the traffic lights.
struct GlassBackButton: View {
    let action: () -> Void

    var body: some View {
        GlassCircleButton(
            icon: "chevron.left",
            help: L10n.shell.back,
            size: 38,
            iconSize: 14,
            keyEquivalent: KeyboardShortcut("[", modifiers: .command),
            action: action
        )
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
            ChromeAvatarVisual(size: size, active: active, hover: hover) {
                avatarContent
            }
        }
        .buttonStyle(GlassBounceButtonStyle())
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
        .animation(GlassMotion.hover, value: hover)
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

// Shared avatar chrome used by the top navigation and contextual user rows.
// Keeping the ring and hover transform in one component prevents detail-page
// avatars from drifting away from the navigation treatment again.
struct ChromeAvatarVisual<Content: View>: View {
    var size: CGFloat = 30
    var active: Bool = false
    var hover: Bool = false
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        size: CGFloat = 30,
        active: Bool = false,
        hover: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.size = size
        self.active = active
        self.hover = hover
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
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
            .frame(width: size + 4, height: size + 4)
            .scaleEffect(reduceMotion ? 1 : (hover ? 1.03 : 1))
            .contentShape(Circle())
    }
}
