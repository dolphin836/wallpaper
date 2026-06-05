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

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearanceSection
            wallpaperSection
            storageSection
            sessionSection
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var appearanceSection: some View {
        sectionCard(title: "Appearance") {
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

    private var wallpaperSection: some View {
        sectionCard(title: "Wallpaper") {
            Toggle(isOn: Binding(get: { manager.autoRotate }, set: { manager.setAutoRotate($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-shuffle").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text("Switch to a random downloaded wallpaper every 4 hours")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
            }.toggleStyle(.switch).tint(Color.accent)
        }
    }

    private var storageSection: some View {
        sectionCard(title: "Storage") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloads folder").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(manager.storageDir.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Reveal in Finder") {
                    try? FileManager.default.createDirectory(at: manager.storageDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(manager.storageDir)
                }
            }
        }
    }

    private var sessionSection: some View {
        sectionCard(title: "Session") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign out").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text("Clear local session and return to the sign-in screen")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button("Sign out", role: .destructive) { auth.logout() }
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
