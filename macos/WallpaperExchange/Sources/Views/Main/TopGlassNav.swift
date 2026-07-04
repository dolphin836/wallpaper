import SwiftUI
import AppKit

// Shared liquid-glass capsule chrome — iOS-style floating glass pill.
// Used by both the centre nav bar and the right icon toolbar so the
// two read as the same family (same height, material, stroke, shadow).
struct GlassPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            // Soft paper tint under the material so the glass stays
            // legible over both bright and dark wallpaper backdrops.
            Capsule().fill(Color.paper.opacity(0.28))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 14, y: 5)
    }
}

// Hairline separator between groups inside a GlassPill.
struct GlassPillDivider: View {
    var body: some View {
        Capsule()
            .fill(Color.ink.opacity(0.16))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }
}

// Icon-only action button sized to match GlassNavItem's height, so an
// icon toolbar pill and the nav pill line up exactly.
struct GlassIconButton: View {
    let icon: String
    let help: String
    var active: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.accent : (hover ? Color.ink : Color.ink2))
                .frame(width: 28, height: 28)
                .background {
                    if active {
                        Circle().fill(Color.accent.opacity(0.13))
                    } else if hover {
                        Circle().fill(Color.ink.opacity(0.07))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focusable(false)
        .help(help)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.14), value: hover)
        .animation(.easeOut(duration: 0.14), value: active)
    }
}

// The single liquid-glass chrome bar fixed at the window's top-centre.
// One shared container, three functional groups separated by hairline
// dividers so they read as distinct clusters:
//   1. Navigation — icon + label segments for the browse destinations
//      (the only group with a selected-capsule state).
//   2. Actions — icon-only buttons (upload, settings, refresh, theme).
//   3. Identity — the avatar chip.
struct GlassChromeBar: View {
    let selection: MainWindow.SidebarItem?
    let onSelect: (MainWindow.SidebarItem) -> Void
    let showUpload: Bool
    let uploadActive: Bool
    let avatarActive: Bool
    let themeIcon: String
    let themeHelp: String
    let onUpload: () -> Void
    let onRefresh: () -> Void
    let onTheme: () -> Void
    let onAvatar: () -> Void

    private static let navItems: [MainWindow.SidebarItem] = [.home, .discover, .weekly, .collections]

    var body: some View {
        GlassPill {
            ForEach(Self.navItems, id: \.self) { item in
                GlassNavItem(
                    item: item,
                    isSelected: item == selection,
                    action: { onSelect(item) }
                )
            }

            GlassPillDivider()

            // Upload needs an account, so the icon only shows once
            // signed in. Settings lives behind the avatar instead of
            // its own icon.
            if showUpload {
                GlassIconButton(
                    icon: "square.and.arrow.up",
                    help: L10n.shell.upload,
                    active: uploadActive,
                    action: onUpload
                )
            }
            GlassIconButton(
                icon: "arrow.clockwise",
                help: L10n.shell.refreshPage,
                action: onRefresh
            )
            GlassIconButton(
                icon: themeIcon,
                help: themeHelp,
                action: onTheme
            )

            GlassPillDivider()

            ToolbarAvatarButton(active: avatarActive, action: onAvatar)
        }
    }
}

private struct GlassNavItem: View {
    let item: MainWindow.SidebarItem
    let isSelected: Bool
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
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                Text(item.label)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.paper.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.14), radius: 5, y: 2)
                } else if hover {
                    Capsule().fill(Color.ink.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focusable(false)
        .help(item.label)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.14), value: hover)
        .animation(.easeOut(duration: 0.14), value: isSelected)
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

    private let size: CGFloat = 24

    var body: some View {
        Button(action: action) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        active ? Color.accent.opacity(0.85) : Color.white.opacity(hover ? 0.65 : 0.35),
                        lineWidth: active ? 1.5 : 1
                    )
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focusable(false)
        .help(auth.isLoggedIn ? L10n.shell.myLibrarySection : L10n.shell.signIn)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.14), value: hover)
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
