import AppKit
import SwiftUI

// Thin top toolbar above the main content. Layout:
//   [title]                  [Upload]                  [shuffle][refresh][downloads][logout]
//                            ^^^^^^^                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//                            centered                  right-aligned circle buttons
// Upload sits on the spatial centerline as the toolbar's primary CTA;
// every other utility button (shuffle, refresh, open Downloads folder,
// sign out) lives in the right cluster.
struct ContentToolbar: View {
    let title: String
    var onRefresh: () -> Void
    var onLogout: () -> Void
    var onUpload: () -> Void
    var onShuffle: () -> Void
    var shuffleOn: Bool
    let isLoggedIn: Bool

    var body: some View {
        ZStack {
            HStack {
                Text(title)
                    .font(.displayLg)
                    .foregroundStyle(Color.ink)
                Spacer()
                HStack(spacing: 10) {
                    circleButton(systemName: shuffleOn ? "shuffle.circle.fill" : "shuffle",
                                 tint: shuffleOn ? Color.accent : Color.ink2,
                                 help: "Auto-shuffle wallpaper every 4 hours",
                                 action: onShuffle)
                    circleButton(systemName: "arrow.clockwise",
                                 help: "Refresh (⌘R)",
                                 action: onRefresh)
                        .keyboardShortcut("r", modifiers: .command)
                    circleButton(systemName: "folder",
                                 help: "Open downloads folder",
                                 action: openDownloads)
                    if isLoggedIn {
                        circleButton(systemName: "rectangle.portrait.and.arrow.right",
                                     help: "Sign out",
                                     action: onLogout)
                    }
                }
            }

            // Centered Upload CTA — anchored to the toolbar midline by
            // sitting in a sibling ZStack layer so it doesn't get pushed
            // around by the variable-width title or right cluster.
            Button(action: onUpload) {
                HStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.up").font(.system(size: 11, weight: .medium))
                    Text("Upload").font(.sans12)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
            .help("Share a wallpaper (⌘U)")
            .keyboardShortcut("u", modifiers: .command)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color.paper.opacity(0.7))
    }

    private func circleButton(systemName: String,
                              tint: Color = Color.ink2,
                              help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.paper))
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // Reveal ~/Library/Application Support/WallpaperExchange/Downloads
    // in Finder. Uses NSWorkspace's selectFile so the folder opens with
    // its contents focused; passing an empty path falls through to
    // open(path:), which opens the folder in a new Finder window.
    private func openDownloads() {
        let dir = WallpaperManager.shared.storageDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
