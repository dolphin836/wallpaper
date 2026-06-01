import SwiftUI
import AppKit

// Left sidebar. Two grouped sections (Browse / My Library), with the
// signed-in identity cell pinned to the bottom (avatar + nickname +
// coin pill + logout). Per the design review the top nav was rolled
// back into a sidebar so the Mac client matches the layout we used
// to have, with the My-section mirroring the web's profile page tabs.
struct MainSidebar: View {
    @Binding var selection: MainWindow.SidebarItem
    @State private var auth = AuthService.shared

    var body: some View {
        List(selection: $selection) {
            // Logo header.
            HStack(spacing: 10) {
                logoChip.frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wallpaper")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ink)
                    Text("EXCHANGE")
                        .font(.kicker).tracking(2.5).foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()

            Section {
                ForEach([MainWindow.SidebarItem.home, .discover, .weekly, .collections], id: \.self) { item in
                    SidebarRow(item: item, isSelected: item == selection)
                        .tag(item)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("BROWSE")
                    .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                    .padding(.top, 4)
            }

            // My Library shows when signed-in. Hide the section entirely
            // for signed-out browsing rather than greying it out —
            // matches the web's profile page (signed-out hits /login).
            if auth.isLoggedIn {
                Section {
                    ForEach([MainWindow.SidebarItem.myUploads, .myCollections, .myDownloads, .myFavorites, .myLikes, .myCoins], id: \.self) { item in
                        SidebarRow(item: item, isSelected: item == selection)
                            .tag(item)
                            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("MY LIBRARY")
                        .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                        .padding(.top, 8)
                }
            }

            // Actions section: Upload (sheet) + Settings (route).
            // Upload always visible — login is prompted on submit if
            // anonymous, matching how the web /upload route behaves.
            Section {
                ForEach([MainWindow.SidebarItem.upload, .settings], id: \.self) { item in
                    SidebarRow(item: item, isSelected: item == selection)
                        .tag(item)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("ACTIONS")
                    .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                    .padding(.top, 8)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { identityFooter }
    }

    @ViewBuilder
    private var logoChip: some View {
        if let url = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "png"),
           let nsImg = NSImage(contentsOf: url) {
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

// Sidebar row with three visual states:
//   • rest     — ink2 icon, ink text, transparent background
//   • hover    — paper-2 tint background (faint mouseover affordance)
//   • selected — accent-tinted background pill + accent icon + accent
//                text; reads cleanly against the warm paper bg, unlike
//                the previous "selected = same black ink" treatment
//                that gave near-zero contrast against the row tint.
struct SidebarRow: View {
    let item: MainWindow.SidebarItem
    let isSelected: Bool
    @State private var hover = false

    private var fg: Color {
        if isSelected { return Color.accent }
        return Color.ink
    }

    private var iconColor: Color {
        if isSelected { return Color.accent }
        if hover      { return Color.ink }
        return Color.ink2
    }

    private var bg: Color {
        if isSelected { return Color.accent.opacity(0.12) }
        if hover      { return Color.ink.opacity(0.05) }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(bg)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
