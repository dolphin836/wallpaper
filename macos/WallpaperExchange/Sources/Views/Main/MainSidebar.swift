import SwiftUI
import AppKit

// Left sidebar. Two grouped sections (Browse / My Library), with the
// signed-in identity cell pinned to the bottom (avatar + nickname +
// coin pill + logout). Per the design review the top nav was rolled
// back into a sidebar so the Mac client matches the layout we used
// to have, with the My-section mirroring the web's profile page tabs.
struct MainSidebar: View {
    @Binding var selection: MainWindow.SidebarItem
    @Binding var collapsed: Bool
    var onUpload: () -> Void
    @State private var auth = AuthService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, WindowChrome.topInset)
                .padding(.horizontal, collapsed ? 8 : 16)
                .padding(.bottom, 10)

            if collapsed {
                collapsedNav
            } else {
                // Drive selection by tap (no List(selection:) — its macOS
                // system highlight paints the row in the OS blue and
                // fights our warm-orange brand).
                List {
                    navSection("BROWSE", topPad: 4,
                               items: [.home, .discover, .weekly, .collections])
                    if auth.isLoggedIn {
                        navSection("MY LIBRARY", topPad: 16,
                                   items: [.myUploads, .myCollections, .myDownloads, .myFavorites, .myLikes, .myCoins])
                    }
                    navSection("ACTIONS", topPad: 16, items: [.upload, .settings])
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) { identityFooter }
    }

    // Brand header. The collapse toggle now lives in the window top bar
    // (on the traffic-light row), so the header is just the brand:
    // expanded shows logo + wordmark, collapsed shows the logo only.
    @ViewBuilder
    private var header: some View {
        if collapsed {
            logoChip.frame(width: 26, height: 26)
                .frame(maxWidth: .infinity)
        } else {
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
            }
        }
    }

    @ViewBuilder
    private func navSection(_ title: String, topPad: CGFloat, items: [MainWindow.SidebarItem]) -> some View {
        Section {
            ForEach(items, id: \.self) { item in
                SidebarRow(item: item, isSelected: item == selection, collapsed: collapsed)
                    .onTapGesture { tap(item) }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .listRowBackground(Color.clear)
            }
        } header: {
            if !collapsed {
                Text(title)
                    .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                    .padding(.top, topPad)
            }
        }
    }

    // Collapsed nav. A plain VStack in a clip-disabled ScrollView (NOT a
    // List) so each icon's hover label can spill out to the RIGHT, past
    // the narrow rail, without being clipped.
    private var collapsedNav: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                collapsedGroup([.home, .discover, .weekly, .collections])
                if auth.isLoggedIn {
                    Color.clear.frame(height: 10)
                    collapsedGroup([.myUploads, .myCollections, .myDownloads, .myFavorites, .myLikes, .myCoins])
                }
                Color.clear.frame(height: 10)
                collapsedGroup([.upload, .settings])
            }
            // No horizontal padding: rows fill the full rail width so the
            // hover-label offset (rowWidth + 4) lands just past the
            // sidebar's right edge. The icon cell is centred within.
            .padding(.top, 6)
        }
        .scrollClipDisabled()
    }

    private func collapsedGroup(_ items: [MainWindow.SidebarItem]) -> some View {
        VStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                SidebarRow(item: item, isSelected: item == selection, collapsed: true)
                    .onTapGesture { tap(item) }
            }
        }
    }

    // Upload opens the sheet without becoming the active selection;
    // everything else routes by setting the selection.
    private func tap(_ item: MainWindow.SidebarItem) {
        if item == .upload { onUpload() } else { selection = item }
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
            if collapsed {
                collapsedFooter
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .overlay(alignment: .top) { Rectangle().fill(Color.hair).frame(height: 1) }
            } else if auth.isLoggedIn, let u = auth.user {
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
        // Round the footer's bottom corners to match the card (the card
        // background is no longer a clipShape, so the footer must clip
        // its own material to the rounded silhouette).
        .clipShape(.rect(bottomLeadingRadius: WindowChrome.radius, bottomTrailingRadius: WindowChrome.radius))
    }

    // Collapsed footer — avatar only (or a sign-in glyph), centred.
    @ViewBuilder
    private var collapsedFooter: some View {
        if auth.isLoggedIn, let u = auth.user {
            avatar(user: u)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))
        } else {
            Button { auth.login() } label: {
                Circle().fill(Color.paper2)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "person").foregroundStyle(Color.muted))
                    .overlay(Circle().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Sign in")
            .pointerCursor()
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
// Sidebar row with clearly separated visual states:
//   • rest      — ink2 icon, ink text, transparent background
//   • hover     — soft ink tint (mouseover affordance) + ink icon
//   • selected  — accent fill + accent semibold text/icon + a leading
//                 accent bar ("you are here")
//   • upload    — accent-tinted as the one call-to-action
// Collapsed: icon only, centred, with a hover label capsule that slides
// out to the RIGHT (same idea as the home grid tiles).
struct SidebarRow: View {
    let item: MainWindow.SidebarItem
    let isSelected: Bool
    var collapsed: Bool = false
    @State private var hover = false

    private var isUpload: Bool { item == .upload }

    private var fg: Color {
        (isSelected || isUpload) ? Color.accent : Color.ink
    }
    private var iconColor: Color {
        if isSelected || isUpload { return Color.accent }
        if hover                  { return Color.ink }
        return Color.ink2
    }
    private var bg: Color {
        if isSelected { return Color.accent.opacity(0.14) }
        if hover      { return isUpload ? Color.accent.opacity(0.12) : Color.ink.opacity(0.06) }
        return .clear
    }

    var body: some View {
        Group {
            if collapsed { collapsedBody } else { expandedBody }
        }
        .contentShape(Rectangle())
        // Native tooltip as a fallback (and for the collapsed labels in
        // case the List clips the custom capsule at the row edge).
        .help(collapsed ? item.label : "")
        .onHover { hovering in
            hover = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var expandedBody: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: (isSelected || isUpload) ? .semibold : .medium))
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(Color.accent).frame(width: 3, height: 15).offset(x: 2)
            }
        }
    }

    private var collapsedBody: some View {
        // Centred icon cell in a full-width rail row. Collapsed active
        // state is just the orange icon + tint (no leading bar).
        Image(systemName: item.icon)
            .font(.system(size: 15, weight: (isSelected || isUpload) ? .semibold : .medium))
            .foregroundStyle(iconColor)
            .frame(width: 36, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            // Hover label flies out to the RIGHT of the rail. Measured
            // against the row width (= full rail width) so it clears the
            // sidebar's right edge with a 4pt gap. The rail doesn't clip
            // (VStack in a scrollClipDisabled ScrollView) and the sidebar
            // is z-above the detail pane, so it shows.
            .overlay(alignment: .leading) {
                if hover {
                    GeometryReader { geo in
                        hoverLabel
                            .fixedSize()
                            .frame(height: geo.size.height, alignment: .center)
                            .offset(x: geo.size.width + 4)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private var hoverLabel: some View {
        Text(item.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 15.0 / 255, green: 12.0 / 255, blue: 8.0 / 255).opacity(0.92)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .transition(.opacity)
    }
}

// Collapse toggle: a small brand-orange circle straddling the sidebar's
// right edge, vertically centred on the logo — the common "edge handle"
// pattern (VS Code / Notion / Linear). Chevron points the way it will
// move: left = collapse, right = expand.
struct SidebarEdgeToggle: View {
    var collapsed: Bool
    var action: () -> Void
    @State private var hover = false
    static let size: CGFloat = 14

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accent)
                .frame(width: Self.size, height: Self.size)
                .overlay(
                    Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: Self.size * 0.5, weight: .black))
                        .foregroundStyle(.white)
                )
                .brightness(hover ? -0.06 : 0)
                .shadow(color: .black.opacity(0.18), radius: 2.5, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(collapsed ? "Expand sidebar" : "Collapse sidebar")
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

extension View {
    // Pointing-hand cursor while hovering. push/pop pairs enter/exit.
    func pointerCursor() -> some View {
        onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
