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
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue
    @AppStorage(LanguagePref.storageKey) private var languageRaw: String = LanguagePref.system.rawValue
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
            storageSection
            autoShuffleSection
            aboutSection
            sessionSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Auto-rotate lives here with the storage settings: its two
    // sources are the local downloads folder (configured below) and a
    // collection — the collection is picked from the My Collections
    // tab, and this panel shows/controls whichever is active.
    private var autoShuffleSection: some View {
        sectionCard(title: L10n.account.autoShuffleKicker) {
            AutoShuffleSettings()
        }
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
            Text(L10n.settings.clearDownloadsConfirmMessage)
        }
    }

    private var aboutSection: some View {
        sectionCard(title: L10n.settings.about) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallpaper Exchange").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(L10n.settings.version(appVersion)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
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
