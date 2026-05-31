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
                    SidebarRow(item: item, isSelected: item == selection).tag(item)
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
                        SidebarRow(item: item, isSelected: item == selection).tag(item)
                    }
                } header: {
                    Text("MY LIBRARY")
                        .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                        .padding(.top, 8)
                }
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
                VStack(alignment: .leading, spacing: 8) {
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
                        Menu {
                            Button("Refresh") { Task { await auth.refreshProfile() } }
                            Divider()
                            Button("Sign out", role: .destructive) { auth.logout() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13)).foregroundStyle(Color.ink2)
                                .frame(width: 26, height: 26)
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .frame(width: 26, height: 26)
                        .fixedSize()
                    }
                    // Coin pill — accent on ink, mirrors the web's
                    // BalancePill.
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.accent)
                            Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8).padding(0.5)
                                .blendMode(.plusLighter)
                        }
                        .frame(width: 16, height: 16)
                        Text("\(u.coins)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.paper)
                            .monospacedDigit()
                        Text("COINS")
                            .font(.kicker).tracking(1.4)
                            .foregroundStyle(Color.paper.opacity(0.7))
                        Spacer()
                    }
                    .padding(.leading, 5).padding(.trailing, 11).padding(.vertical, 5)
                    .background(Capsule().fill(Color.ink))
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

struct SidebarRow: View {
    let item: MainWindow.SidebarItem
    let isSelected: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.accent : Color.ink2)
            Text(item.label).font(.sans13).foregroundStyle(Color.ink)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}
