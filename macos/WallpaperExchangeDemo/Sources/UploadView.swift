import SwiftUI
import UniformTypeIdentifiers

// Upload sheet. Two-state flow: pick → metadata. Demo only — selecting
// a file just advances to the metadata form; submitting closes the
// sheet without contacting any server.
struct UploadView: View {
    var onClose: () -> Void

    @State private var step: Step = .pick
    @State private var droppedURL: URL?
    @State private var isDropTargeting = false
    @State private var title = ""
    @State private var description = ""
    @State private var category = "Nature"
    @State private var tags = ""
    @State private var isAIGenerated = false
    @State private var allowDerivatives = true

    enum Step { case pick, meta }

    var body: some View {
        ZStack {
            Color.dPaper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Rectangle().fill(Color.dHair).frame(height: 1)
                switch step {
                case .pick: pickStep
                case .meta: metaStep
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Kicker(text: step == .pick ? "Step 1 of 2 · Pick a file" : "Step 2 of 2 · Add details")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dInk2)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.dPaper2))
                    .overlay(Circle().stroke(Color.dHair, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Share a wallpaper")
                    .font(.dDisplay32)
                    .foregroundStyle(Color.dInk)
                Text("PNG, JPG, HEIC, or MP4. We'll generate device-sized variants automatically.")
                    .font(.dSans13)
                    .foregroundStyle(Color.dMuted)
            }

            // Big drop zone. Dashed border + center-aligned chevron icon.
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6]))
                .foregroundStyle(isDropTargeting ? Color.dAccent : Color.dHair)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isDropTargeting ? Color.dAccentSoft.opacity(0.45) : Color.dPaper2.opacity(0.5))
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 280)
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "arrow.up.doc.on.clipboard")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(isDropTargeting ? Color.dAccent : Color.dMuted)
                        VStack(spacing: 4) {
                            Text(isDropTargeting ? "Drop to upload" : "Drag a wallpaper here")
                                .font(.dDisplay18)
                                .foregroundStyle(Color.dInk)
                            Text("or")
                                .font(.dMono10).tracking(1.5)
                                .foregroundStyle(Color.dMuted)
                        }
                        Button(action: pickFile) {
                            Text("Choose a file…")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.dInk))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDrop(of: [.image, .movie, .fileURL], isTargeted: $isDropTargeting, perform: handleDrop)

            HStack(spacing: 22) {
                bulletPoint(icon: "circle.grid.cross", title: "All sizes generated", body: "Desktop, laptop, phone, tablet variants.")
                bulletPoint(icon: "person.crop.circle.badge.checkmark", title: "Earn coins", body: "+1 coin per upload, +1 per download.")
                bulletPoint(icon: "shield", title: "Review", body: "Goes to moderation before going public.")
            }
            Spacer()
        }
        .padding(28)
    }

    private func bulletPoint(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.dAccent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.dSans12).foregroundStyle(Color.dInk)
                Text(body).font(.dMono10).tracking(0.5).foregroundStyle(Color.dMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaStep: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                // Left rail — file preview from droppedURL if available.
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.dPaper2)
                    if let url = droppedURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.dMuted)
                            }
                        }
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.dMuted)
                    }
                }
                .frame(width: 280, height: 200)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.dHair, lineWidth: 1))

                // Right column — fields.
                VStack(alignment: .leading, spacing: 16) {
                    field(label: "TITLE", value: $title, placeholder: "Misty Pine Forest…")
                    field(label: "DESCRIPTION", value: $description, placeholder: "Optional · what's in the shot, where it was taken", multiline: true)
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker(text: "CATEGORY")
                            Picker("", selection: $category) {
                                ForEach(["Nature", "City", "Anime", "Abstract", "Animal", "Space", "Other", "Minimal", "Tech", "Game"], id: \.self) { c in
                                    Text(c).tag(c)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 180)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker(text: "TAGS · comma sep")
                            TextField("forest, mist, mountain", text: $tags)
                                .textFieldStyle(.plain)
                                .font(.dSans12)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.dPaper))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dHair, lineWidth: 1))
                        }
                    }

                    Toggle(isOn: $isAIGenerated) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("AI-generated").font(.dSans12).foregroundStyle(Color.dInk)
                            Text("Tag this if a model produced or substantially edited it.").font(.dMono10).foregroundStyle(Color.dMuted)
                        }
                    }
                    Toggle(isOn: $allowDerivatives) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Allow derivatives").font(.dSans12).foregroundStyle(Color.dInk)
                            Text("Others can build collections, remix, etc.").font(.dMono10).foregroundStyle(Color.dMuted)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(action: { step = .pick }) {
                    Text("Back").font(.dSans12)
                        .foregroundStyle(Color.dInk2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.dPaper))
                        .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Goes to moderation queue.").font(.dMono10).tracking(0.6).foregroundStyle(Color.dMuted)
                Button(action: onClose) {
                    Text("Submit").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.dAccent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.thinMaterial)
            .overlay(alignment: .top) { Rectangle().fill(Color.dHair).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func field(label: String, value: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(text: label)
            if multiline {
                TextEditor(text: value)
                    .scrollContentBackground(.hidden)
                    .font(.dSans12)
                    .padding(8)
                    .frame(minHeight: 70)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.dPaper))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dHair, lineWidth: 1))
            } else {
                TextField(placeholder, text: value)
                    .textFieldStyle(.plain)
                    .font(.dSans12)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.dPaper))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dHair, lineWidth: 1))
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                droppedURL = url
                step = .meta
            }
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
            step = .meta
        }
    }
}
