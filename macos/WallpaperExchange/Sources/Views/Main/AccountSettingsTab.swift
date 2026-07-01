import SwiftUI
import AppKit

// The Mac-only "Settings" tab inside AccountView. App-level preferences
// only — account identity (avatar / nickname / bio / password) lives in
// the shared header above, and the likes/favorites/downloads visibility
// toggles now live on their own tabs, so this tab no longer repeats any
// of the user's profile info.
struct AccountSettingsTab: View {
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
    @State private var showClearConfirm = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var localSizeText: String {
        ByteCountFormatter.string(fromByteCount: manager.totalLocalBytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearanceSection
            languageSection
            particleSection
            storageSection
            aboutSection
            sessionSection
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var appearanceSection: some View {
        sectionCard(title: L10n.settings.appearance) {
            HStack(spacing: 8) {
                ForEach(AppearancePref.allCases, id: \.self) { pref in
                    let isOn = appearanceRaw == pref.rawValue
                    Button(action: { appearanceRaw = pref.rawValue }) {
                        HStack(spacing: 6) {
                            Image(systemName: pref.icon).font(.system(size: 11, weight: .medium))
                            Text(pref.label).font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        }
                        .foregroundStyle(isOn ? Color.accent : Color.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.accent.opacity(0.12) : Color.paper2))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Color.accent.opacity(0.35) : Color.hair, lineWidth: 1))
                    }.buttonStyle(.plain).pointerCursor()
                }
            }
        }
    }

    // Language picker mirrors the Appearance chip row. Labels render in their
    // own script (never translated); App.swift re-mounts the whole tree via
    // .id(languageRaw) so the switch takes effect immediately.
    private var languageSection: some View {
        sectionCard(title: L10n.common.language) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(LanguagePref.allCases, id: \.self) { pref in
                        let isOn = languageRaw == pref.rawValue
                        let label = pref == .system ? L10n.common.languageSystem : pref.resolved.nativeName
                        Button(action: { languageRaw = pref.rawValue }) {
                            Text(label).font(.system(size: 12, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? Color.accent : Color.ink2)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.accent.opacity(0.12) : Color.paper2))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Color.accent.opacity(0.35) : Color.hair, lineWidth: 1))
                        }.buttonStyle(.plain).pointerCursor()
                    }
                }
                Text(L10n.common.languageFootnote).font(.system(size: 11)).foregroundStyle(Color.muted)
            }
        }
    }

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
        .pointerCursor()
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
        .pointerCursor()
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
        case .terrainPillars: L10n.settings.particleTerrainPillars
        case .terrainFoam: L10n.settings.particleTerrainFoam
        case .terrainIrregular: L10n.settings.particleTerrainIrregular
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

    private var storageSection: some View {
        sectionCard(title: L10n.settings.storage) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.settings.downloadsFolder).font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(manager.storageDir.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(L10n.settings.revealInFinder) {
                    try? FileManager.default.createDirectory(at: manager.storageDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(manager.storageDir)
                }
            }
            Divider().background(Color.hair)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.settings.localCache).font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(L10n.settings.localCacheUsed(localSizeText))
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button(L10n.settings.clearDownloads, role: .destructive) { showClearConfirm = true }
                    .disabled(manager.totalLocalBytes == 0)
            }
        }
        .confirmationDialog(L10n.settings.clearDownloadsConfirmTitle, isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(L10n.settings.clearDownloadsDelete(localSizeText), role: .destructive) { manager.clearDownloads() }
            Button(L10n.common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.settings.clearDownloadsMessage)
        }
    }

    private var aboutSection: some View {
        sectionCard(title: L10n.settings.about) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallpaper Exchange").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(L10n.settings.appVersion(appVersion)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button(L10n.settings.checkForUpdates) { UpdateService.shared.checkManually() }
            }
        }
    }

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

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5).foregroundStyle(Color.muted).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.paper.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hair, lineWidth: 1))
        }
    }
}
