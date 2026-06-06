import SwiftUI
import AppKit

// Mac App tab. On the web this links to /download/mac with the
// release manifest + changelog. On the Mac itself we're already
// running it — show the current version, a "Check for Updates"
// button, and the recent changelog from the bundled mac_release.json.
struct MacAppView: View {
    @State private var release: MacRelease?
    @State private var loading = false
    @State private var loadError: String?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                hero
                changelog
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 900).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await load() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: "You're running")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Wallpaper Exchange")
                    .font(.display32).foregroundStyle(Color.ink)
                Text("v\(currentVersion)")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.muted)
            }
            Text("Native menu-bar quick actions plus a Dock-visible main window. Drag wallpapers straight to your desktop, set per-display in detail, or let auto-shuffle rotate every 4 hours.")
                .font(.sans13).foregroundStyle(Color.muted)
                .frame(maxWidth: 600, alignment: .leading)
            HStack(spacing: 10) {
                Button(action: { Task { @MainActor in UpdateService.shared.checkManually() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        Text("Check for updates").font(.sans12)
                    }
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)

                Button(action: openInBrowser) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11, weight: .medium))
                        Text("Open the web app").font(.sans12)
                    }
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.paper))
                    .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
    }

    private var changelog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "Release notes")
            if loading && release == nil {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                SkeletonLine(width: 82, height: 16)
                                Spacer()
                                SkeletonLine(width: 86, height: 10)
                            }
                            SkeletonLine(width: 420, height: 11)
                            SkeletonLine(width: 300, height: 11)
                        }
                    }
                }
            } else if let err = loadError {
                RemoteLoadErrorView(title: "Could not load release notes", message: err) {
                    Task { await load() }
                }
            } else if let r = release, let entries = r.releases, !entries.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(entries.prefix(6), id: \.version) { entry in
                        entryRow(entry: entry, isCurrent: entry.version == currentVersion)
                    }
                }
            } else {
                Text("No release notes available offline.")
                    .font(.sans12).foregroundStyle(Color.muted)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func entryRow(entry: MacReleaseEntry, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("v\(entry.version)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ink)
                if isCurrent {
                    Text("CURRENT")
                        .font(.kicker).tracking(1.5)
                        .foregroundStyle(Color.accent)
                }
                Spacer()
                Text(entry.releasedAt ?? "")
                    .font(.mono10).tracking(0.5).foregroundStyle(Color.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.notes ?? [], id: \.self) { note in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·").foregroundStyle(Color.muted)
                        Text(note).font(.sans12).foregroundStyle(Color.ink2)
                    }
                }
            }
        }
    }

    private func load() async {
        loadError = nil
        loading = true; defer { loading = false }
        do {
            release = try await APIClient.shared.fetchMacRelease()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func openInBrowser() {
        if let url = URL(string: "https://wallpaperexchange.com") {
            NSWorkspace.shared.open(url)
        }
    }
}
