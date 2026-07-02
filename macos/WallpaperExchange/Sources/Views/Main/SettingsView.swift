import AppKit
import SwiftUI

// Unified settings page. Hosts everything that used to live in the
// top toolbar (refresh, logout, open downloads, auto-rotate) plus
// app-level prefs (appearance) and account info.
//
// Profile editing (avatar / nickname / bio / password) is not yet
// wired — the Mac APIClient lacks the corresponding endpoints. For
// now there's a stub block with a "Open profile" link that pushes
// the user's ProfileView; a follow-up will add the actual mutation
// endpoints (POST /users/me/avatar, PATCH /users/me, etc.).
struct SettingsView: View {
    var onOpenProfile: (String) -> Void

    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue
    @AppStorage(LanguagePref.storageKey) private var languageRaw: String = LanguagePref.system.rawValue

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // Page title
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.settings.kicker)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Color.muted)
                    Text(L10n.settings.title)
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ink)
                }

                accountSection
                appearanceSection
                languageSection
                storageSection
                if auth.isLoggedIn { sessionSection }
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // ─── Account ─────────────────────────────────────────────────
    private var accountSection: some View {
        sectionCard(title: L10n.settings.account) {
            if let u = auth.user {
                HStack(spacing: 14) {
                    avatarView(user: u)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(u.nickname.isEmpty ? u.username : u.nickname)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.ink)
                        Text("@\(u.username)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.muted)
                        MiniCoinPill(coins: u.coins)
                        .padding(.top, 2)
                    }
                    Spacer()
                    Button(L10n.settings.openProfile) {
                        onOpenProfile(u.username)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                Divider().background(Color.hair).padding(.vertical, 4)
                Text(L10n.settings.profileEditingNote)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.muted)
            } else {
                HStack {
                    Text(L10n.settings.notSignedIn)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.muted)
                    Spacer()
                    Button(L10n.settings.signIn) { auth.login() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func avatarView(user: User) -> some View {
        if !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL) {
            CachedAsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.paper2
                    Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                        .font(.displayMd).foregroundStyle(Color.ink)
                }
            }
        } else {
            ZStack {
                Color.paper2
                Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                    .font(.displayMd).foregroundStyle(Color.ink)
            }
        }
    }

    // ─── Appearance ──────────────────────────────────────────────
    private var appearanceSection: some View {
        sectionCard(title: L10n.settings.appearance) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.settings.theme)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach(AppearancePref.allCases, id: \.self) { pref in
                        themeChip(pref: pref)
                    }
                }
            }
        }
    }

    private func themeChip(pref: AppearancePref) -> some View {
        let isOn = appearanceRaw == pref.rawValue
        return Button(action: { appearanceRaw = pref.rawValue }) {
            HStack(spacing: 6) {
                Image(systemName: pref.icon).font(.system(size: 11, weight: .medium))
                Text(pref.label).font(.system(size: 12, weight: isOn ? .semibold : .regular))
            }
            .foregroundStyle(isOn ? Color.accent : Color.ink2)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.accent.opacity(0.12) : Color.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? Color.accent.opacity(0.35) : Color.hair, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // ─── Language ────────────────────────────────────────────────
    // Same chip row as Appearance. Language names render in their own
    // script (never translated); the window root re-mounts via .id() so
    // the switch takes effect immediately.
    private var languageSection: some View {
        sectionCard(title: L10n.common.language) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(LanguagePref.allCases, id: \.self) { pref in
                        languageChip(pref: pref)
                    }
                }
                Text(L10n.common.languageFootnote)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func languageChip(pref: LanguagePref) -> some View {
        let isOn = languageRaw == pref.rawValue
        let label = pref == .system ? L10n.common.languageSystem : pref.resolved.nativeName
        return Button(action: { languageRaw = pref.rawValue }) {
            Text(label)
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.accent : Color.ink2)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? Color.accent.opacity(0.12) : Color.paper2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? Color.accent.opacity(0.35) : Color.hair, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // ─── Storage ─────────────────────────────────────────────────
    private var storageSection: some View {
        sectionCard(title: L10n.settings.storage) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.settings.downloadsFolder).font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(manager.storageDir.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(L10n.settings.revealInFinder) {
                    try? FileManager.default.createDirectory(at: manager.storageDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(manager.storageDir)
                }
            }
        }
    }

    // ─── Session ─────────────────────────────────────────────────
    private var sessionSection: some View {
        sectionCard(title: L10n.settings.session) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.settings.signOut).font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(L10n.settings.signOutDesc)
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button(L10n.settings.signOut, role: .destructive) { auth.logout() }
            }
        }
    }

    // ─── Section card chrome ─────────────────────────────────────
    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.muted)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.paper.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1)
            )
        }
    }
}

// ─── AppearancePref ──────────────────────────────────────────────
// Persisted via @AppStorage so the choice survives relaunches.
// Applied at the WindowGroup root via `.preferredColorScheme`.
enum AppearancePref: String, CaseIterable {
    case system, light, dark

    static let storageKey = "app.appearance"

    var label: String {
        switch self {
        case .system: L10n.settings.themeSystem
        case .light:  L10n.settings.themeLight
        case .dark:   L10n.settings.themeDark
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    static func fromStorage(_ raw: String) -> AppearancePref {
        AppearancePref(rawValue: raw) ?? .system
    }

    static func applyToApp(_ raw: String) {
        NSApp.appearance = fromStorage(raw).nsAppearance
    }
}
