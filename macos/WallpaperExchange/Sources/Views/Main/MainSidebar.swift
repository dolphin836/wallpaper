import SwiftUI

// Left-side navigation. Two grouped sections (Browse / My Library)
// mirroring the web's IA, plus a footer with the signed-in profile
// chip and a prominent accent CTA at the bottom for upload.
struct MainSidebar: View {
    @Binding var selection: MainWindow.SidebarItem
    var onUpload: () -> Void
    @State private var auth = AuthService.shared

    var body: some View {
        List(selection: $selection) {
            // Logo row at the top — replaces the title bar (we run
            // with .unified showsTitle=false).
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.ink)
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.paper)
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wallpaper").font(.displayLg).foregroundStyle(Color.ink)
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
                ForEach([MainWindow.SidebarItem.discover, .weekly, .device, .categories], id: \.self) { item in
                    SidebarRow(item: item, isSelected: item == selection).tag(item)
                }
            } header: {
                Text("BROWSE")
                    .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                    .padding(.top, 4)
            }

            Section {
                ForEach([MainWindow.SidebarItem.downloads, .collections, .liked, .uploaded], id: \.self) { item in
                    SidebarRow(item: item, isSelected: item == selection).tag(item)
                }
            } header: {
                Text("MY LIBRARY")
                    .font(.kicker).tracking(1.8).foregroundStyle(Color.muted)
                    .padding(.top, 8)
            }

            // Bottom accent CTA for upload. Lives inside the List so
            // the keyboard scroll/focus paths behave naturally; non-
            // selectable so the sidebar selection doesn't bounce here.
            Button(action: onUpload) {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Share a wallpaper").font(.sans12)
                    Spacer()
                    Text("⌘U").font(.mono10).tracking(0.5).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("u", modifiers: .command)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
            .padding(.top, 6)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            footerCell
        }
    }

    private var footerCell: some View {
        HStack(spacing: 10) {
            if auth.isLoggedIn, let u = auth.user {
                ZStack {
                    Color.paper2
                    if !u.avatarURL.isEmpty, let url = URL(string: u.avatarURL) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Text(String((u.nickname.isEmpty ? u.username : u.nickname).prefix(1)).uppercased())
                                .font(.displayMd).foregroundStyle(Color.ink)
                        }
                    } else {
                        Text(String((u.nickname.isEmpty ? u.username : u.nickname).prefix(1)).uppercased())
                            .font(.displayMd).foregroundStyle(Color.ink)
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    Text(u.nickname.isEmpty ? u.username : u.nickname)
                        .font(.sans12).foregroundStyle(Color.ink).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(Color.accent).frame(width: 7, height: 7)
                        Text("\(u.coins) coins")
                            .font(.mono10).tracking(0.5).foregroundStyle(Color.muted)
                    }
                }
            } else {
                Circle().fill(Color.paper2)
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "person").foregroundStyle(Color.muted))
                Text("Not signed in")
                    .font(.sans12).foregroundStyle(Color.muted)
            }
            Spacer()
            if auth.isLoggedIn {
                Button(action: { auth.logout() }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink2)
                }
                .buttonStyle(.plain)
                .help("Sign out")
            } else {
                Button("Sign in") { auth.login() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hair).frame(height: 1)
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
            Text(item.label)
                .font(.sans13)
                .foregroundStyle(Color.ink)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}
