import SwiftUI
import AppKit

// Horizontal top navigation, modelled on the web's TopNav. Logo + nav
// item links + centered search field + coin pill + avatar/menu. The
// underline indicator slides under the active tab; clicking a tab
// flips `tab` on the parent.
struct TopNavBar: View {
    @Binding var tab: MainWindow.TopTab
    @Binding var search: String
    var onCommitSearch: () -> Void
    var onUpload: () -> Void
    var onProfile: () -> Void
    var onLogin: () -> Void
    var onLogout: () -> Void
    let auth: AuthService
    let manager: WallpaperManager

    @State private var userMenuOpen = false

    var body: some View {
        HStack(spacing: 16) {
            // Logo cluster
            HStack(spacing: 8) {
                logoImage
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wallpaper")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ink)
                    Text("EXCHANGE")
                        .font(.kicker).tracking(2.5)
                        .foregroundStyle(Color.muted)
                }
            }
            .padding(.trailing, 4)

            // Nav items
            HStack(spacing: 22) {
                ForEach(MainWindow.TopTab.allCases, id: \.self) { t in
                    NavItem(label: t.rawValue, active: t == tab) { tab = t }
                }
            }

            Spacer()

            // Search field — committed on submit; the parent pushes a
            // search-results page onto the nav stack when committed.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                TextField("Search wallpapers, tags, devices…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.sans12)
                    .frame(width: 260)
                    .onSubmit { onCommitSearch() }
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.paper2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hair, lineWidth: 1))
            )

            // Right cluster — upload + shuffle + coin pill + avatar.
            HStack(spacing: 10) {
                Button(action: onUpload) {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.up").font(.system(size: 11, weight: .medium))
                        Text("Upload").font(.sans12)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.accent))
                }
                .buttonStyle(.plain)
                .help("Share a wallpaper (⌘U)")
                .keyboardShortcut("u", modifiers: .command)

                Button(action: { manager.setAutoRotate(!manager.autoRotate) }) {
                    Image(systemName: manager.autoRotate ? "shuffle.circle.fill" : "shuffle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(manager.autoRotate ? Color.accent : Color.ink2)
                }
                .buttonStyle(.plain)
                .help("Auto-shuffle wallpaper every 4 hours")

                if auth.isLoggedIn, let u = auth.user {
                    coinPill(coins: u.coins)
                    avatarMenu(user: u)
                } else {
                    Button("Sign in") { onLogin() }.controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.paper.opacity(0.92))
    }

    @ViewBuilder
    private var logoImage: some View {
        if let url = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "png"),
           let nsImg = NSImage(contentsOf: url) {
            Image(nsImage: nsImg).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            // Fallback — fail gracefully if the resource didn't get
            // bundled (e.g., running `swift run` without the build script
            // that copies Resources/).
            RoundedRectangle(cornerRadius: 5).fill(Color.ink)
                .overlay(Image(systemName: "rectangle.stack.badge.play")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.paper))
        }
    }

    private func coinPill(coins: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.accent).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8).padding(0.5))
            Text("\(coins)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.paper)
                .monospacedDigit()
        }
        .padding(.leading, 5).padding(.trailing, 11).padding(.vertical, 4)
        .background(Capsule().fill(Color.ink))
    }

    private func avatarMenu(user: User) -> some View {
        Menu {
            Button("My Profile", action: onProfile)
            Divider()
            Button("Sign out", role: .destructive, action: onLogout)
        } label: {
            Circle()
                .fill(Color.paper2)
                .overlay {
                    if !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                                .font(.displayMd).foregroundStyle(Color.ink)
                        }
                    } else {
                        Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                            .font(.displayMd).foregroundStyle(Color.ink)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 30)
        .fixedSize()
    }
}

struct NavItem: View {
    let label: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Color.ink : Color.ink2)
                Rectangle()
                    .fill(active ? Color.ink : .clear)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }
}
