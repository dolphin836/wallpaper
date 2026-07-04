import SwiftUI
import AppKit

// Liquid-glass navigation pill fixed at the window's top-centre —
// iOS-style floating glass capsule. Only the four browse destinations
// live here; actions (upload / settings / avatar) stay in the icon
// toolbar on the right side of the chrome row.
struct GlassNavBar: View {
    let selection: MainWindow.SidebarItem?
    let onSelect: (MainWindow.SidebarItem) -> Void

    private static let items: [MainWindow.SidebarItem] = [.home, .discover, .weekly, .collections]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.self) { item in
                GlassNavItem(
                    item: item,
                    isSelected: item == selection,
                    action: { onSelect(item) }
                )
            }
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
            .padding(.vertical, 6)
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

// Avatar chip at the right end of the chrome row. Signed-in shows the
// user's avatar (initial fallback); signed-out shows a person glyph and
// starts the login flow on click.
struct ToolbarAvatarButton: View {
    var active: Bool = false
    let action: () -> Void

    @State private var auth = AuthService.shared
    @State private var hover = false

    private let size: CGFloat = 26

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
                .shadow(color: Color.black.opacity(0.18), radius: 4, y: 1)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func initialBadge(for user: User) -> some View {
        ZStack {
            Circle().fill(Color.paper2)
            Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink)
        }
    }
}
