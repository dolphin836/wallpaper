import SwiftUI
import PhotosUI

// Photo upload: PhotosPicker → preview → multipart POST /wallpapers.
// The backend pipeline (image worker) takes over after upload — autotag,
// thumbnail generation, then the admin review queue — so the client only
// needs to deliver the original file. Earns 1 coin per accepted upload.
struct UploadView: View {
    @Environment(AuthService.self) private var auth

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: PlatformImage?

    enum UploadState: Equatable {
        case idle
        case uploading(Double)
        case done
        case failed(String)
    }
    @State private var state: UploadState = .idle
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(kicker: "Share & earn a coin", title: "Upload")
                        .padding(.top, 6)
                    if !auth.isLoggedIn {
                        signedOutPrompt
                    } else {
                        pickerSection
                        if previewImage != nil {
                            previewSection
                            submitSection
                        }
                        rulesCard
                    }
                }
                .padding(12)
            }
            .background(Color.paper)
            .navigationTitle("")
            .inlineNavTitle()
            .sheet(isPresented: $showAuth) { AuthView() }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                state = .idle
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        imageData = data
                        previewImage = PlatformImage(data: data)
                    }
                }
            }
        }
    }

    private var signedOutPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sign in to share wallpapers and earn coins.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Sign In / Register") { showAuth = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 60)
    }

    private var pickerSection: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 34))
                Text(previewImage == nil ? "Choose a photo" : "Choose a different photo")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, previewImage == nil ? 48 : 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let previewImage {
            VStack(alignment: .leading, spacing: 6) {
                Image(platformImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 360)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("\(Int(previewImage.pixelSize.width))×\(Int(previewImage.pixelSize.height)) px · \(ByteCountFormatter.string(fromByteCount: Int64(imageData?.count ?? 0), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var submitSection: some View {
        switch state {
        case .idle:
            Button {
                submit()
            } label: {
                Text("Upload")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lightText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        case .uploading(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                Text("Uploading… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            VStack(spacing: 8) {
                Label("Uploaded — pending review", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.medium))
                Text("Your wallpaper will appear publicly once approved. The upload reward lands after processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Upload another") {
                    pickerItem = nil
                    imageData = nil
                    previewImage = nil
                    state = .idle
                }
                .buttonStyle(.bordered)
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
                Button("Try again") { state = .idle }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(text: "House rules")
            Group {
                Text("• Original or properly licensed images only")
                Text("• No watermarks, text overlays or people")
                Text("• Higher resolution ranks better, 4K+ preferred")
                Text("• Every upload goes through review before publishing")
            }
            .font(.caption)
            .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .paperCard()
    }

    private func submit() {
        guard let imageData else { return }
        state = .uploading(0)
        // PhotosPicker's transferable is JPEG/PNG/HEIC bytes; sniff the
        // magic to label the part correctly.
        let (filename, mime) = Self.sniffImageType(imageData)
        Task {
            do {
                try await APIClient.shared.uploadWallpaperData(imageData, filename: filename, mime: mime) { progress in
                    Task { @MainActor in
                        if case .uploading = state {
                            state = .uploading(progress)
                        }
                    }
                }
                state = .done
                await auth.refreshCoins()
            } catch {
                state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private static func sniffImageType(_ data: Data) -> (filename: String, mime: String) {
        if data.starts(with: [0xFF, 0xD8]) {
            return ("wallpaper.jpg", "image/jpeg")
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return ("wallpaper.png", "image/png")
        }
        // HEIC/HEIF: 'ftyp' box at offset 4.
        if data.count > 12, data[4] == 0x66, data[5] == 0x74, data[6] == 0x79, data[7] == 0x70 {
            return ("wallpaper.heic", "image/heic")
        }
        return ("wallpaper.jpg", "image/jpeg")
    }
}
