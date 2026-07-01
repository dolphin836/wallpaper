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
    @State private var particles = ParticleWallpaperController.shared
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue
    @AppStorage(LanguagePref.storageKey) private var languageRaw: String = LanguagePref.system.rawValue
    @AppStorage(ParticleWallpaperController.presetDefaultsKey) private var particlePresetRaw: String = ParticleWallpaperPreset.starfield.rawValue
    @AppStorage(ParticleWallpaperController.densityDefaultsKey) private var particleDensity: Double = ParticleWallpaperConfig.default.density
    @AppStorage(ParticleWallpaperController.speedDefaultsKey) private var particleSpeed: Double = ParticleWallpaperConfig.default.speed
    @AppStorage(ParticleWallpaperController.brightnessDefaultsKey) private var particleBrightness: Double = ParticleWallpaperConfig.default.brightness
    @AppStorage(ParticleWallpaperController.targetDefaultsKey) private var particleTargetID: String = WallpaperDisplayTarget.allID

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
                particleSection
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

    // ─── Particle wallpapers ────────────────────────────────────
    private var particleSection: some View {
        sectionCard(title: L10n.settings.particleWallpapers) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.accent.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.settings.particleDesc)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        particleStatusPill
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.settings.particlePreset)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                    ChipFlow(spacing: 8) {
                        ForEach(ParticleWallpaperPreset.allCases) { preset in
                            particlePresetChip(preset)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.settings.particleDisplay)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                    ChipFlow(spacing: 8) {
                        ForEach(ParticleWallpaperController.displayTargets()) { target in
                            particleTargetChip(target)
                        }
                    }
                }

                VStack(spacing: 10) {
                    particleSlider(title: L10n.settings.particleDensity, value: $particleDensity)
                    particleSlider(title: L10n.settings.particleSpeed, value: $particleSpeed)
                    particleSlider(title: L10n.settings.particleBrightness, value: $particleBrightness)
                }

                HStack(spacing: 10) {
                    Button(L10n.settings.particleApply) {
                        applyParticleWallpaper()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(L10n.settings.particleStop) {
                        particles.stop()
                    }
                    .disabled(!particles.isRunning)
                    Spacer()
                }
            }
        }
    }

    private var particleStatusPill: some View {
        let running = particles.isRunning
        return HStack(spacing: 5) {
            Circle()
                .fill(running ? Color.accent : Color.muted.opacity(0.55))
                .frame(width: 6, height: 6)
            Text(running ? L10n.settings.particleRunning : L10n.settings.particleStopped)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(running ? Color.accent : Color.muted)
    }

    private func particlePresetChip(_ preset: ParticleWallpaperPreset) -> some View {
        let isOn = particlePresetRaw == preset.rawValue
        return Button(action: { particlePresetRaw = preset.rawValue }) {
            HStack(spacing: 7) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(particlePresetLabel(preset))
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
            }
            .foregroundStyle(isOn ? Color.accent : Color.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isOn ? Color.accent.opacity(0.13) : Color.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isOn ? Color.accent.opacity(0.38) : Color.hair, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func particleTargetChip(_ target: WallpaperDisplayTarget) -> some View {
        let isOn = particleTargetID == target.id
        return Button(action: { particleTargetID = target.id }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: target.isAll ? "rectangle.stack" : "display")
                        .font(.system(size: 11, weight: .semibold))
                    Text(target.name)
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .lineLimit(1)
                }
                Text(target.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? Color.accent.opacity(0.78) : Color.muted)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Color.accent : Color.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: 150, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? Color.accent.opacity(0.12) : Color.paper2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.accent.opacity(0.38) : Color.hair, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func particleSlider(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.ink)
                .frame(width: 72, alignment: .leading)
            Slider(value: value, in: 0.1...1.0)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.muted)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func particlePresetLabel(_ preset: ParticleWallpaperPreset) -> String {
        switch preset {
        case .starfield: L10n.settings.particleStarfield
        case .snow: L10n.settings.particleSnow
        case .rain: L10n.settings.particleRain
        case .fireflies: L10n.settings.particleFireflies
        case .aurora: L10n.settings.particleAurora
        case .embers: L10n.settings.particleEmbers
        case .audioTerrain: L10n.settings.particleAudioTerrain
        case .sonicSilk: L10n.settings.particleSonicSilk
        case .sonicTunnel: L10n.settings.particleSonicTunnel
        case .sonicOrbit: L10n.settings.particleSonicOrbit
        case .vinylPulse: L10n.settings.particleVinylPulse
        case .wallpaperPulse: L10n.settings.particleWallpaperPulse
        }
    }

    private func applyParticleWallpaper() {
        let preset = ParticleWallpaperPreset(rawValue: particlePresetRaw) ?? .starfield
        let config = ParticleWallpaperConfig(
            density: particleDensity,
            speed: particleSpeed,
            brightness: particleBrightness,
            frameRate: ParticleWallpaperConfig.default.frameRate
        )
        let targets = ParticleWallpaperController.displayTargets()
        let target = targets.first { $0.id == particleTargetID } ?? targets.first ?? WallpaperDisplayTarget(
            id: WallpaperDisplayTarget.allID,
            name: L10n.detail.wallpaperAllDisplays,
            detail: L10n.detail.wallpaperAllDisplaysDetail(0),
            screenKey: nil,
            isMain: false
        )
        particles.start(preset: preset, config: config, target: target)
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
