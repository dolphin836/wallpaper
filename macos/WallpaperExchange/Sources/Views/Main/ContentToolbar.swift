import SwiftUI

// Thin top toolbar above the main content. The sidebar owns user
// identity now, so the toolbar carries just the section title,
// search field, and primary actions (upload + shuffle).
struct ContentToolbar: View {
    let title: String
    @Binding var search: String
    var onCommitSearch: () -> Void
    var onUpload: () -> Void
    var onShuffle: () -> Void
    var shuffleOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.displayLg)
                .foregroundStyle(Color.ink)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                TextField("Search wallpapers, tags, devices…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.sans12)
                    .frame(width: 280)
                    .onSubmit { onCommitSearch() }
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.paper2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hair, lineWidth: 1))
            )

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
        .background(Color.paper.opacity(0.92))
    }
}
