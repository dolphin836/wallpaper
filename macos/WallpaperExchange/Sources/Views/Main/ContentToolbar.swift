import SwiftUI

// Thin top toolbar above the main content. Per the v2.3 review the
// search field moved out (Discover owns search now), and Refresh +
// Sign-out moved up here from the sidebar menu.
struct ContentToolbar: View {
    let title: String
    var onRefresh: () -> Void
    var onLogout: () -> Void
    var onUpload: () -> Void
    var onShuffle: () -> Void
    var shuffleOn: Bool
    let isLoggedIn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.displayLg)
                .foregroundStyle(Color.ink)

            Spacer()

            Button(action: onShuffle) {
                Image(systemName: shuffleOn ? "shuffle.circle.fill" : "shuffle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(shuffleOn ? Color.accent : Color.ink2)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.paper))
                    .overlay(Circle().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Auto-shuffle wallpaper every 4 hours")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.paper))
                    .overlay(Circle().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Refresh (⌘R)")
            .keyboardShortcut("r", modifiers: .command)

            if isLoggedIn {
                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.paper))
                        .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Sign out")
            }

            Button(action: onUpload) {
                HStack(spacing: 5) {
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color.paper.opacity(0.7))
    }
}
