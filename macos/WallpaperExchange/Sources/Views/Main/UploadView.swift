import SwiftUI
import UniformTypeIdentifiers

// Upload sheet. v1 sends users to the web UploadPage (the TUS chunked
// upload flow lives there). Native uploading from the Mac is a Stage 2
// item — the sheet here pre-validates the file + collects metadata so
// the web roundtrip is fast, and we don't burn an engineering week
// reimplementing TUS in Swift just to ship v2's chrome.
struct UploadView: View {
    var onClose: () -> Void

    @State private var droppedURL: URL?
    @State private var isDropTargeting = false
    @State private var auth = AuthService.shared

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Rectangle().fill(Color.hair).frame(height: 1)
                if auth.isLoggedIn { content } else { signedOutPrompt }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Kicker(text: "Share a wallpaper")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.paper2))
                    .overlay(Circle().stroke(Color.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drop a wallpaper to start.")
                    .font(.display24)
                    .foregroundStyle(Color.ink)
                Text("PNG, JPG, HEIC, or MP4. We'll generate device-sized variants automatically once it's published.")
                    .font(.sans13)
                    .foregroundStyle(Color.muted)
            }

            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6]))
                .foregroundStyle(isDropTargeting ? Color.accent : Color.hair)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isDropTargeting ? Color.accentSoft.opacity(0.45) : Color.paper2.opacity(0.5))
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 280)
                .overlay { dropContents }
                .onDrop(of: [.image, .movie, .fileURL], isTargeted: $isDropTargeting, perform: handleDrop)

            HStack(spacing: 22) {
                bullet(icon: "circle.grid.cross", title: "All sizes generated", body: "Desktop, laptop, phone, tablet variants.")
                bullet(icon: "person.crop.circle.badge.checkmark", title: "Earn coins", body: "+1 per upload, +1 per download.")
                bullet(icon: "shield", title: "Review", body: "Goes to moderation before publishing.")
            }
            Spacer()
        }
        .padding(28)
    }

    @ViewBuilder
    private var dropContents: some View {
        VStack(spacing: 14) {
            Image(systemName: droppedURL == nil ? "arrow.up.doc.on.clipboard" : "doc.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isDropTargeting ? Color.accent : Color.muted)
            VStack(spacing: 4) {
                if let url = droppedURL {
                    Text(url.lastPathComponent)
                        .font(.displayLg).foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text("Continue in browser to publish")
                        .font(.mono10).tracking(0.6).foregroundStyle(Color.muted)
                } else {
                    Text(isDropTargeting ? "Drop to upload" : "Drag a wallpaper here")
                        .font(.displayLg).foregroundStyle(Color.ink)
                    Text("or")
                        .font(.mono10).tracking(1.5).foregroundStyle(Color.muted)
                }
            }
            HStack(spacing: 8) {
                Button(action: pickFile) {
                    Text("Choose a file…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                if droppedURL != nil {
                    Button(action: openWebUpload) {
                        Text("Open web uploader →")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(Color.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var signedOutPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.muted)
            Text("Sign in to share").font(.displayLg).foregroundStyle(Color.ink)
            Text("Uploads need a Wallpaper Exchange account.")
                .font(.sans13).foregroundStyle(Color.muted)
            Button(action: { auth.login() }) {
                Text("Sign in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sans12).foregroundStyle(Color.ink)
                Text(body).font(.mono10).tracking(0.5).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in droppedURL = url }
        }
        return true
    }
    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            droppedURL = url
        }
    }
    private func openWebUpload() {
        if let url = URL(string: "https://wallpaperexchange.com/upload") {
            NSWorkspace.shared.open(url)
        }
        onClose()
    }
}
