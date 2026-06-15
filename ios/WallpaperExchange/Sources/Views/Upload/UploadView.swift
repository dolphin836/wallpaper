import SwiftUI
import PhotosUI

// Photo upload: PhotosPicker → preview → multipart POST /wallpapers.
// The backend pipeline (image worker) takes over after upload — autotag,
// thumbnail generation, then the admin review queue — so the client only
// needs to deliver the original file. Earns 1 coin per accepted upload.
struct UploadView: View {
    var onClose: (() -> Void)?

    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss

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

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(kicker: s.uploadKicker, title: s.upload)
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
            .navigationTitle(s.upload)
            .inlineNavTitle()
            .showNavBarCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(s.cancel) { close() }
                }
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
                    .authSheetPresentation()
            }
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
        let s = L10n.strings(for: prefs.language)

        return VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(s.uploadSignedOutMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(s.signInRegister) { showAuth = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var pickerSection: some View {
        let s = L10n.strings(for: prefs.language)

        return PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 34))
                Text(previewImage == nil ? s.uploadChoosePhoto : s.uploadChooseDifferentPhoto)
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
        let s = L10n.strings(for: prefs.language)

        switch state {
        case .idle:
            Button {
                submit()
            } label: {
                Text(s.upload)
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
                Text(String(format: s.uploadProgress, Int(progress * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            VStack(spacing: 8) {
                Label(s.uploadPendingReview, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.medium))
                Text(s.uploadPendingMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(s.uploadAnother) {
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
                Button(s.uploadTryAgain) { state = .idle }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var rulesCard: some View {
        let s = L10n.strings(for: prefs.language)

        return VStack(alignment: .leading, spacing: 6) {
            Kicker(text: s.uploadRulesTitle)
            Group {
                Text("• \(s.uploadRuleLicensed)")
                Text("• \(s.uploadRuleNoWatermarks)")
                Text("• \(s.uploadRuleResolution)")
                Text("• \(s.uploadRuleReview)")
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

    private func close() {
        onClose?()
        dismiss()
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
