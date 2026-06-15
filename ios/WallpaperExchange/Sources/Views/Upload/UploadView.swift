import SwiftUI
import PhotosUI

// Photo upload: PhotosPicker -> local queue -> multipart POST /wallpapers.
// The backend pipeline takes over after upload: autotag, thumbnail generation,
// and admin review. iOS mirrors the web upload queue for multi-photo batches.
struct UploadView: View {
    var onClose: (() -> Void)?

    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    private static let maxFiles = 20

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var queue: [UploadQueueItem] = []
    @State private var uploading = false
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
                        if !queue.isEmpty {
                            queueSection
                            uploadBar
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
            .onChange(of: pickerItems) { _, newItems in
                addPickerItems(newItems)
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
        let slots = max(0, Self.maxFiles - queue.count)

        return PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: max(1, slots),
            matching: .images,
            photoLibrary: .shared()
        ) {
            VStack(spacing: queue.isEmpty ? 9 : 7) {
                Image(systemName: queue.isEmpty ? "photo.badge.plus" : "plus.circle.fill")
                    .font(.system(size: queue.isEmpty ? 34 : 22, weight: .semibold))
                Text(queue.isEmpty ? s.uploadChoosePhotos : String(format: s.uploadAddMorePhotos, queue.count, Self.maxFiles))
                    .font(.subheadline.weight(.semibold))
                Text(String(format: s.uploadBatchHint, Self.maxFiles))
                    .font(.caption)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(slots == 0 || uploading ? Color.muted : Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, queue.isEmpty ? 42 : 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle((slots == 0 || uploading ? Color.hair : Color.accentColor.opacity(0.5)))
            )
        }
        .disabled(slots == 0 || uploading)
    }

    private var queueSection: some View {
        let s = L10n.strings(for: prefs.language)
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: String(format: s.uploadSelectedCount, queue.count), title: s.uploadQueueTitle)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(queue) { item in
                    UploadQueueTile(item: item, uploading: uploading) {
                        removeItem(item.id)
                    }
                }
            }
        }
    }

    private var uploadBar: some View {
        let s = L10n.strings(for: prefs.language)
        let ready = queue.filter(\.needsUpload).count
        let done = queue.filter(\.isSuccess).count
        let failed = queue.filter(\.isFailed).count
        let allDone = !queue.isEmpty && done == queue.count
        let progress = overallProgress

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if uploading {
                    ProgressView(value: progress)
                    Text("\(done)/\(queue.count) · \(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.muted)
                        .frame(minWidth: 68, alignment: .trailing)
                } else if allDone {
                    Label(s.uploadAllDone, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.green)
                } else {
                    Text(String(format: s.uploadReadyCount, ready))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    if done > 0 {
                        Text("· \(String(format: s.uploadDoneCount, done))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.green)
                    }
                    if failed > 0 {
                        Text("· \(String(format: s.uploadFailedCount, failed))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red)
                    }
                }
            }

            HStack(spacing: 10) {
                if allDone {
                    Button {
                        queue.removeAll()
                        pickerItems = []
                    } label: {
                        Label(s.uploadAnother, systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        submit()
                    } label: {
                        Label(uploadButtonTitle(strings: s, ready: ready, failed: failed), systemImage: uploading ? "arrow.triangle.2.circlepath" : "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(uploading || ready == 0)
                }
            }
        }
        .padding(12)
        .paperCard()
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

    private var overallProgress: Double {
        guard !queue.isEmpty else { return 0 }
        let total = queue.reduce(0.0) { partial, item in
            switch item.status {
            case .success:
                return partial + 1
            case .uploading:
                return partial + item.progress
            case .pending, .failed:
                return partial
            }
        }
        return min(max(total / Double(queue.count), 0), 1)
    }

    private func uploadButtonTitle(strings s: AppStrings, ready: Int, failed: Int) -> String {
        if failed > 0, ready == failed {
            return s.uploadRetryFailed
        }
        if ready <= 1 {
            return s.upload
        }
        return String(format: s.uploadUploadMany, ready)
    }

    private func addPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !uploading else { return }
        let slots = max(0, Self.maxFiles - queue.count)
        guard slots > 0 else {
            pickerItems = []
            return
        }
        let selected = Array(items.prefix(slots))
        pickerItems = []

        Task {
            var additions: [UploadQueueItem] = []
            for item in selected {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = PlatformImage(data: data) else {
                    continue
                }
                let (filename, mime) = Self.sniffImageType(data)
                additions.append(UploadQueueItem(
                    data: data,
                    previewImage: image,
                    pixelSize: image.pixelSize,
                    fileSize: data.count,
                    filename: filename,
                    mime: mime
                ))
            }
            guard !additions.isEmpty else { return }
            await MainActor.run {
                queue.append(contentsOf: additions)
            }
        }
    }

    private func removeItem(_ id: UUID) {
        guard !uploading else { return }
        queue.removeAll { $0.id == id }
    }

    private func submit() {
        guard !uploading else { return }
        let ids = queue.filter(\.needsUpload).map(\.id)
        guard !ids.isEmpty else { return }

        uploading = true
        Task {
            for id in ids {
                guard let item = await MainActor.run(body: { queue.first(where: { $0.id == id }) }) else { continue }
                await MainActor.run {
                    updateItem(id) {
                        $0.status = .uploading
                        $0.progress = 0
                    }
                }
                do {
                    try await APIClient.shared.uploadWallpaperData(item.data, filename: item.filename, mime: item.mime) { progress in
                        Task { @MainActor in
                            updateItem(id) {
                                $0.status = .uploading
                                $0.progress = progress
                            }
                        }
                    }
                    await MainActor.run {
                        updateItem(id) {
                            $0.status = .success
                            $0.progress = 1
                        }
                    }
                } catch {
                    let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    await MainActor.run {
                        updateItem(id) {
                            $0.status = .failed(message)
                            $0.progress = 0
                        }
                    }
                }
            }
            _ = await auth.refreshCoins()
            await MainActor.run {
                uploading = false
            }
        }
    }

    private func updateItem(_ id: UUID, mutate: (inout UploadQueueItem) -> Void) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        mutate(&queue[index])
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

private enum UploadQueueStatus: Equatable {
    case pending
    case uploading
    case success
    case failed(String)
}

private struct UploadQueueItem: Identifiable {
    let id = UUID()
    let data: Data
    let previewImage: PlatformImage
    let pixelSize: CGSize
    let fileSize: Int
    let filename: String
    let mime: String
    var status: UploadQueueStatus = .pending
    var progress: Double = 0

    var needsUpload: Bool {
        switch status {
        case .pending, .failed:
            return true
        case .uploading, .success:
            return false
        }
    }

    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }
}

private struct UploadQueueTile: View {
    let item: UploadQueueItem
    let uploading: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Image(platformImage: item.previewImage)
                    .resizable()
                    .aspectRatio(DeviceScreenRatio.value, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 202)
                    .clipped()
                    .background(Color.paper3)

                statusOverlay

                if !uploading, !item.isSuccess {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.lightText)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

            Text(metaText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.muted)
                .lineLimit(1)

            if let message = item.errorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .uploading:
            VStack(spacing: 8) {
                ProgressView(value: item.progress)
                    .tint(Color.lightText)
                    .padding(.horizontal, 18)
                Text("\(Int(item.progress * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.lightText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.34))
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.green)
                .padding(8)
                .background(.black.opacity(0.32), in: Circle())
                .padding(7)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.red)
                .padding(8)
                .background(.black.opacity(0.32), in: Circle())
                .padding(7)
        }
    }

    private var borderColor: Color {
        switch item.status {
        case .pending:
            return Color.hair
        case .uploading:
            return Color.accent.opacity(0.8)
        case .success:
            return Color.green.opacity(0.65)
        case .failed:
            return Color.red.opacity(0.7)
        }
    }

    private var metaText: String {
        "\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) · \(ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))"
    }
}
