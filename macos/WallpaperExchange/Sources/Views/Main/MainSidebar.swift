import SwiftUI
import AppKit

// Left sidebar. Two grouped sections (Browse / My Library), with the
// signed-in identity cell pinned to the bottom (avatar + nickname +
// coin pill + logout). Per the design review the top nav was rolled
// back into a sidebar so the Mac client matches the layout we used
// to have, with the My-section mirroring the web's profile page tabs.
struct MainSidebar: View {
    @Binding var selection: MainWindow.SidebarItem
    var onUpload: () -> Void
    @State private var auth = AuthService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Logo header — pulled out of the List so we can pad it
            // exactly the same amount as the detail pane's top
            // padding. Keeping it inside the List left it subject to
            // List's own variable inset (different in full-screen vs
            // windowed), which is why the sidebar and detail tops
            // drifted relative to each other.
            HStack(spacing: 10) {
                logoChip.frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wallpaper")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ink)
                    Text("EXCHANGE")
                        .font(.kicker).tracking(2.5).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                // Icon-only Upload + Settings, top-right of the brand —
                // replaces the old ACTIONS sidebar group. Each expands
                // on hover to reveal its label beside the icon.
                HStack(spacing: 4) {
                    SidebarActionButton(icon: "square.and.arrow.up", label: "Upload",
                                        accent: true, action: onUpload)
                    SidebarActionButton(icon: "gearshape", label: "Settings",
                                        accent: false, isActive: selection == .settings,
                                        action: { selection = .settings })
                }
            }
            // Logo sits BELOW the traffic lights on its own row —
            // standard left-aligned padding (no offset for buttons,
            // which live on the row above).
            .padding(.top, WindowChrome.topInset)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // No List(selection:) — its macOS system highlight paints the
            // selected row in the OS accent (default blue) and forces the
            // label colour, fighting our warm-orange brand. Drive
            // selection by tap instead and express active state purely
            // through SidebarRow's own orange styling.
            List {
                Section {
                    ForEach([MainWindow.SidebarItem.home, .discover, .weekly, .collections], id: \.self) { item in
                        SidebarRow(item: item, isSelected: item == selection)
                            .onTapGesture { selection = item }
                            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("BROWSE")
                        .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                        .padding(.top, 4)
                }

                // My Library shows when signed-in. Hide the section
                // entirely for signed-out browsing — matches the web.
                if auth.isLoggedIn {
                    Section {
                        ForEach([MainWindow.SidebarItem.myUploads, .myCollections, .myDownloads, .myFavorites, .myLikes, .myCoins], id: \.self) { item in
                            SidebarRow(item: item, isSelected: item == selection)
                                .onTapGesture { selection = item }
                                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("MY LIBRARY")
                            .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                            .padding(.top, 16)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom) { identityFooter }
    }

    @ViewBuilder
    private var logoChip: some View {
        // Embedded brand mark — renders in dev and release alike (no
        // Bundle.main dependency). Falls back to a glyph only if the
        // embedded asset somehow fails to decode.
        if let nsImg = BrandAsset.logo {
            Image(nsImage: nsImg).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 5).fill(Color.ink)
                .overlay(Image(systemName: "rectangle.stack.badge.play")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.paper))
        }
    }

    // Identity cell pinned to the sidebar's bottom edge. Shows avatar,
    // name (or @handle), coin pill, and a logout button. Tapping the
    // cell when signed-in pushes to /user/<self>; signed-out shows a
    // single "Sign in" button.
    private var identityFooter: some View {
        Group {
            if auth.isLoggedIn, let u = auth.user {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        avatar(user: u)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u.nickname.isEmpty ? u.username : u.nickname)
                                .font(.sans12).foregroundStyle(Color.ink).lineLimit(1)
                            Text("@\(u.username)")
                                .font(.mono10).tracking(0.5)
                                .foregroundStyle(Color.muted).lineLimit(1)
                        }
                        Spacer()
                    }
                    // Web-style BalancePill — warm gradient, minted-
                    // coin disc that flips on hover.
                    BalancePill(coins: u.coins)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.thinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.hair).frame(height: 1)
                }
            } else {
                HStack(spacing: 10) {
                    Circle().fill(Color.paper2)
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "person").foregroundStyle(Color.muted))
                        .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Not signed in").font(.sans12).foregroundStyle(Color.ink)
                        Text("Sign in to view My Library")
                            .font(.mono10).tracking(0.4).foregroundStyle(Color.muted).lineLimit(1)
                    }
                    Spacer()
                    Button("Sign in") { auth.login() }.controlSize(.small)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.thinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.hair).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func avatar(user: User) -> some View {
        if !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL) {
            CachedAsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                    .font(.displayMd).foregroundStyle(Color.ink)
            }
        } else {
            ZStack {
                Color.paper2
                Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                    .font(.displayMd).foregroundStyle(Color.ink)
            }
        }
    }
}

// Sidebar row with clearly separated visual states:
//   • rest      — ink2 icon, ink text, transparent background
//   • hover     — soft ink tint (mouseover affordance) + ink icon
//   • selected  — accent fill + accent semibold text/icon + a leading
//                 accent bar ("you are here"), distinct from the
//                 softer hover tint
//   • primary   — Upload only: standing accent tint so the ACTIONS
//                 group reads as a call-to-action, not navigation
struct SidebarRow: View {
    let item: MainWindow.SidebarItem
    let isSelected: Bool
    @State private var hover = false

    private var fg: Color {
        isSelected ? Color.accent : Color.ink
    }

    private var iconColor: Color {
        if isSelected { return Color.accent }
        if hover      { return Color.ink }
        return Color.ink2
    }

    private var bg: Color {
        if isSelected { return Color.accent.opacity(0.14) }
        if hover      { return Color.ink.opacity(0.06) }
        return .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .frame(width: 18)
                .foregroundStyle(iconColor)
            Text(item.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(fg)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg)
        )
        // Leading accent bar marks the active row — a hard "you are
        // here" signal that reads differently from the soft hover tint.
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(Color.accent)
                    .frame(width: 3, height: 15)
                    .offset(x: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hover = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// Brand-header action button (Upload / Settings). Icon-only at rest;
// on hover it grows into a pill and slides its label in to the right of
// the icon. `accent` marks the primary (Upload) styling; `isActive`
// gives Settings its selected accent tint.
private struct SidebarActionButton: View {
    let icon: String
    let label: String
    var accent: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    @State private var hover = false

    private var fg: Color {
        if accent { return Color.accent }
        if isActive { return Color.accent }
        return hover ? Color.ink : Color.ink2
    }

    private var bg: Color {
        if accent { return hover ? Color.accent.opacity(0.16) : .clear }
        if isActive { return Color.accent.opacity(0.14) }
        return hover ? Color.ink.opacity(0.06) : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                if hover {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(fg)
            .frame(height: 28)
            .frame(minWidth: 28)
            .padding(.horizontal, hover ? 9 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.16), value: hover)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
