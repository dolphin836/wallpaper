import SwiftUI
import UniformTypeIdentifiers
import AppKit

private let uploadMaxBytes = 200 * 1024 * 1024
private let uploadMaxFiles = 20
private let pendingUploadLimit = 12

private enum UploadStatus: Equatable {
    case pending
    case uploading
    case success
    case error(String)
}

private enum UploadKind {
    case image
    case video
}

private struct UploadItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let byteSize: Int
    let kind: UploadKind
    let thumbnail: NSImage?
    var status: UploadStatus = .pending
    var progress: Int = 0
}

struct UploadView: View {
    var onCancel: () -> Void = {}

    @State private var auth = AuthService.shared
    @State private var files: [UploadItem] = []
    @State private var isDropTargeting = false
    @State private var uploading = false
    @State private var message: String?
    @State private var pendingUploads: [Wallpaper] = []
    @State private var pendingTotal = 0
    @State private var pendingLoading = false
    @State private var pendingLoaded = false
    @State private var pendingError: String?

    private var totalDone: Int { files.filter { $0.status == .success }.count }
    private var totalError: Int {
        files.filter {
            if case .error = $0.status { return true }
            return false
        }.count
    }
    private var totalPending: Int {
        files.filter { item in
            switch item.status {
            case .pending, .uploading: return true
            case .success, .error: return false
            }
        }.count
    }
    private var allDone: Bool { !files.isEmpty && files.allSatisfy { $0.status == .success } }
    private var showPendingUploadsSection: Bool {
        pendingLoading || pendingError != nil || !pendingUploads.isEmpty
    }
    private var overallProgress: Int {
        guard !files.isEmpty else { return 0 }
        let total = files.reduce(0) { partial, file in
            partial + (file.status == .success ? 100 : file.progress)
        }
        return Int((Double(total) / Double(files.count)).rounded())
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            uploadMesh

            if auth.isLoggedIn {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        reviewNotice
                            .padding(.top, 28)
                        dropZone
                            .padding(.top, 28)
                        if !files.isEmpty {
                            queueSection
                                .padding(.top, 32)
                        }
                        if showPendingUploadsSection {
                            pendingUploadsSection
                                .padding(.top, files.isEmpty ? 34 : 36)
                        }
                        Color.clear.frame(height: files.isEmpty ? 48 : 106)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 32)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                signedOutPrompt
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !files.isEmpty {
                uploadBar
            }
        }
        .task(id: auth.user?.username ?? "") {
            if auth.isLoggedIn {
                await loadPendingUploads()
            }
        }
    }

    private var uploadMesh: some View {
        LinearGradient(
            stops: [
                .init(color: Color.accentSoft.opacity(0.52), location: 0),
                .init(color: Color(red: 0.98, green: 0.76, blue: 0.55).opacity(0.34), location: 0.48),
                .init(color: Color.paper.opacity(0.98), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blur(radius: 62)
        .opacity(0.72)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: "Contribute · Wallpaper Exchange")
            Text("Share ")
                .font(.system(size: 48, weight: .regular, design: .serif))
                .foregroundStyle(Color.ink)
            + Text("what's on your screen.")
                .font(.system(size: 48, weight: .medium, design: .serif))
                .foregroundStyle(Color.accent)
            Text("Drop images (JPG / PNG / HEIC, up to \(uploadMaxFiles) at a time) or a single video (MP4 / MOV / WebM / MKV). Each file capped at 200 MB. Every upload earns one coin once it clears review.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Color.ink2)
                .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var reviewNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(Color.accent)
                .frame(width: 10, height: 10)
                .shadow(color: Color.accent.opacity(0.32), radius: 0, x: 0, y: 0)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("ADMIN REVIEW")
                    .font(.mono10)
                    .tracking(1.8)
                    .foregroundStyle(Color.ink2)
                Text("Everything goes through review before showing up publicly. You can see status on your profile; videos may take a minute longer because we transcode them.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 720, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accent.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.hair.blended(with: Color.accent, fraction: 0.30), lineWidth: 1)
        )
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isDropTargeting ? Color.accentSoft.opacity(0.52) : Color.accent.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isDropTargeting ? Color.accent : Color.hair.blended(with: Color.accent, fraction: 0.28),
                        style: StrokeStyle(lineWidth: 1.6, dash: [6, 6])
                    )
            )
            .frame(minHeight: files.isEmpty ? 280 : 78)
            .overlay {
                if files.isEmpty {
                    emptyDropContents
                } else {
                    compactDropContents
                }
            }
            .scaleEffect(isDropTargeting ? 1.005 : 1)
            .animation(.easeOut(duration: 0.18), value: isDropTargeting)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeting, perform: handleDrop)
    }

    private var emptyDropContents: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.accent)
            }
            Text(isDropTargeting ? "Drop them here" : "Drop images here")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Color.ink)
            HStack(spacing: 4) {
                Text("or")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink2)
                Button(action: pickFiles) {
                    Text("click to pick from your computer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                metaChip("JPG · PNG · HEIC")
                Text("·").font(.mono10).foregroundStyle(Color.muted)
                metaChip("MP4 · MOV · WebM")
                Text("·").font(.mono10).foregroundStyle(Color.muted)
                metaChip("≤ 200 MB")
                Text("·").font(.mono10).foregroundStyle(Color.muted)
                metaChip("Up to \(uploadMaxFiles) files")
            }
            .padding(.top, 4)
        }
    }

    private var compactDropContents: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.accent)
            }
            Button(action: pickFiles) {
                Text("Add more · \(files.count) / \(uploadMaxFiles)")
                    .font(.mono11)
                    .tracking(1.2)
                    .foregroundStyle(uploading || files.count >= uploadMaxFiles ? Color.muted : Color.ink)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.clear))
                    .overlay(Capsule().stroke(Color.hair.blended(with: Color.accent, fraction: 0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(uploading || files.count >= uploadMaxFiles)
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("QUEUE · \(files.count)")
                    .font(.mono10)
                    .tracking(1.4)
                    .foregroundStyle(Color.muted)
                if totalDone > 0 {
                    Text("· \(totalDone) done")
                        .font(.mono10)
                        .tracking(1.0)
                        .foregroundStyle(Color.accent)
                }
                if totalError > 0 {
                    Text("· \(totalError) failed")
                        .font(.mono10)
                        .tracking(1.0)
                        .foregroundStyle(Color.warn)
                }
                Rectangle().fill(Color.hair).frame(height: 1)
            }
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(files) { file in
                    UploadTileView(
                        item: file,
                        uploading: uploading,
                        onRemove: { removeFile(file.id) }
                    )
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 14, alignment: .top)]
    }

    private var pendingUploadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabelRule(text: "PENDING · \(pendingLoaded ? "\(pendingTotal)" : "…")")
            Text("Wallpapers still being processed or waiting on admin review. Each tile shows its exact stage; they enter the public archive once approved.")
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 680, alignment: .leading)

            if pendingLoading && pendingUploads.isEmpty {
                WallpaperGridSkeleton(columns: pendingGridColumns, count: 12, spacing: 14, aspectRatio: 3.0 / 2.0, cornerRadius: 10)
            } else if let pendingError {
                RemoteLoadErrorView(title: "Could not load pending uploads", message: pendingError) {
                    Task { await loadPendingUploads() }
                }
            } else {
                LazyVGrid(columns: pendingGridColumns, spacing: 14) {
                    ForEach(pendingUploads) { wallpaper in
                        PendingUploadTileView(wallpaper: wallpaper)
                    }
                }
            }
        }
    }

    private var pendingGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top)]
    }

    private var uploadBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if uploading {
                    HStack(spacing: 10) {
                        progressTrack(value: overallProgress)
                        Text("\(totalDone)/\(files.count) · \(overallProgress)%")
                            .font(.mono11)
                            .tracking(0.5)
                            .foregroundStyle(Color.ink2)
                            .monospacedDigit()
                    }
                } else if allDone {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accent)
                        Text("All set. Your uploads are pending review.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink)
                    }
                } else {
                    Text("\(totalPending) \(totalPending == 1 ? "file" : "files") ready to upload\(totalError > 0 ? " · \(totalError) need a retry" : "")")
                        .font(.system(size: 13))
                        .foregroundStyle(totalError > 0 ? Color.warn : Color.ink2)
                }
                if let message {
                    Text(message)
                        .font(.mono10)
                        .tracking(0.4)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !uploading && !allDone {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.mono11)
                        .tracking(1.4)
                        .foregroundStyle(Color.muted)
                        .textCase(.uppercase)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            Button(action: { Task { await handleUpload() } }) {
                HStack(spacing: 8) {
                    if uploading {
                        ProgressView()
                            .scaleEffect(0.58)
                            .frame(width: 14, height: 14)
                    }
                    Text(uploadButtonTitle)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.paper)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.ink))
            }
            .buttonStyle(.plain)
            .disabled(uploading || allDone)
            .opacity(uploading || allDone ? 0.55 : 1)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(Rectangle().fill(Color.hair).frame(height: 1), alignment: .top)
    }

    private var uploadButtonTitle: String {
        if uploading { return "Uploading" }
        if totalError > 0 { return "Retry failed" }
        if allDone { return "Done" }
        return "Upload \(files.count) \(files.count == 1 ? "file" : "files") →"
    }

    private var signedOutPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.muted)
            Text("Sign in to share")
                .font(.displayLg)
                .foregroundStyle(Color.ink)
            Text("Uploads need a Wallpaper Exchange account.")
                .font(.sans13)
                .foregroundStyle(Color.muted)
            Button(action: { auth.login() }) {
                Text("Sign in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.mono10)
            .tracking(1.2)
            .foregroundStyle(Color.muted)
    }

    private func progressTrack(value: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.paper2)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.blended(with: Color.ink, fraction: 0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * CGFloat(value) / 100))
            }
        }
        .frame(height: 4)
    }

    private func pickFiles() {
        guard !uploading else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !uploading else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let raw = item as? URL {
                    url = raw
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    url = URL(string: string)
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            addFiles(urls)
        }
        return true
    }

    private func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        message = nil
        let remaining = uploadMaxFiles - files.count
        guard remaining > 0 else {
            message = "Maximum \(uploadMaxFiles) files allowed."
            return
        }

        let candidates = urls.prefix(remaining).compactMap(makeItem)
        let oversized = candidates.filter { $0.byteSize > uploadMaxBytes }
        let accepted = candidates.filter { $0.byteSize <= uploadMaxBytes }
        if !oversized.isEmpty {
            message = "\(oversized.count) file\(oversized.count == 1 ? "" : "s") exceed 200 MB and were skipped."
        }
        guard !accepted.isEmpty else { return }

        let incomingHasVideo = accepted.contains { $0.kind == .video }
        let existingHasVideo = files.contains { $0.kind == .video }
        let existingHasImage = files.contains { $0.kind == .image }

        if incomingHasVideo {
            if accepted.count > 1 {
                message = "Drop one video at a time."
                return
            }
            if existingHasImage {
                message = "Clear the image batch before adding a video."
                return
            }
            if existingHasVideo {
                message = "Only one video per upload."
                return
            }
        } else if existingHasVideo {
            message = "Clear the queued video before adding images."
            return
        }

        files.append(contentsOf: accepted)
    }

    private func makeItem(url: URL) -> UploadItem? {
        guard let kind = kind(for: url) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return UploadItem(
            url: url,
            name: url.lastPathComponent,
            byteSize: size,
            kind: kind,
            thumbnail: kind == .image ? NSImage(contentsOf: url) : nil
        )
    }

    private func kind(for url: URL) -> UploadKind? {
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "webm", "mkv"].contains(ext) { return .video }
        if ["jpg", "jpeg", "png", "heic", "heif", "webp", "avif"].contains(ext) { return .image }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .movie) { return .video }
            if type.conforms(to: .image) { return .image }
        }
        return nil
    }

    private func removeFile(_ id: UUID) {
        guard !uploading else { return }
        files.removeAll { $0.id == id }
        if files.isEmpty {
            message = nil
        }
    }

    private func handleUpload() async {
        guard !files.isEmpty, !uploading else { return }
        uploading = true
        message = nil
        var succeeded = 0
        var failed = 0

        for file in files {
            if file.status == .success {
                succeeded += 1
                continue
            }
            updateFile(file.id) {
                $0.status = .uploading
                $0.progress = 0
            }
            do {
                if file.kind == .video {
                    try await APIClient.shared.uploadVideoTus(fileURL: file.url) { value in
                        Task { @MainActor in
                            updateFile(file.id) { $0.progress = Int((value * 100).rounded()) }
                        }
                    }
                } else {
                    try await APIClient.shared.uploadWallpaperFile(fileURL: file.url) { value in
                        Task { @MainActor in
                            updateFile(file.id) { $0.progress = Int((value * 100).rounded()) }
                        }
                    }
                }
                updateFile(file.id) {
                    $0.status = .success
                    $0.progress = 100
                }
                succeeded += 1
            } catch {
                let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                updateFile(file.id) {
                    $0.status = .error(text)
                    $0.progress = 0
                }
                failed += 1
            }
        }

        uploading = false
        await auth.refreshProfile()
        if succeeded > 0 {
            await loadPendingUploads()
        }
        if failed == 0 {
            message = succeeded == 1
                ? "Upload received. It will appear after review."
                : "\(succeeded) uploads received. They will appear after review."
        } else {
            message = "\(succeeded) succeeded, \(failed) failed."
        }
    }

    private func updateFile(_ id: UUID, mutate: (inout UploadItem) -> Void) {
        guard let idx = files.firstIndex(where: { $0.id == id }) else { return }
        mutate(&files[idx])
    }

    private func loadPendingUploads() async {
        guard let username = auth.user?.username, !username.isEmpty else {
            pendingUploads = []
            pendingTotal = 0
            pendingLoaded = true
            pendingError = nil
            return
        }

        pendingLoading = true
        pendingError = nil
        defer {
            pendingLoading = false
            pendingLoaded = true
        }

        do {
            let data = try await APIClient.shared.fetchUserUploads(
                username: username,
                limit: pendingUploadLimit,
                status: "0,5",
                compatibleOnly: false
            )
            pendingUploads = data.items
            pendingTotal = data.total ?? data.items.count
        } catch {
            pendingUploads = []
            pendingTotal = 0
            pendingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct UploadTileView: View {
    let item: UploadItem
    let uploading: Bool
    var onRemove: () -> Void

    private var isError: Bool {
        if case .error = item.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.paper2)
                media
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                statusOverlay
                if !uploading && item.status != .success {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.lightText)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.58)))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)

            HStack(spacing: 8) {
                Text(kindLabel)
                    .font(.mono10)
                    .tracking(0.5)
                    .foregroundStyle(Color.muted)
                    .frame(width: 34, alignment: .leading)
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        if let thumbnail = item.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            VStack(spacing: 7) {
                Image(systemName: item.kind == .video ? "play.rectangle.fill" : "doc.fill")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.muted)
                Text(item.kind == .video ? "VIDEO" : "FILE")
                    .font(.mono10)
                    .tracking(1.0)
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color.paper2, Color.paper], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .uploading:
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.72)
                    .tint(Color.lightText)
                tileProgress(value: item.progress)
                    .frame(width: 86)
                Text("\(item.progress)%")
                    .font(.mono10)
                    .foregroundStyle(Color.lightText)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.54))
        case .success:
            ZStack {
                Color(hex: "#3e9e5e").opacity(0.42)
                Circle()
                    .fill(Color(hex: "#3e9e5e"))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.paper)
                    )
            }
        case .error(let message):
            VStack(spacing: 7) {
                Circle()
                    .fill(Color.warn)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.paper)
                    )
                Text(message)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.warn.opacity(0.72))
        }
    }

    private var borderColor: Color {
        if item.status == .success { return Color(hex: "#3e9e5e").opacity(0.55) }
        if isError { return Color.warn.opacity(0.65) }
        return Color.hair
    }

    private var kindLabel: String {
        item.kind == .video ? "VID" : "IMG"
    }

    private func tileProgress(value: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.lightText.opacity(0.32))
                Capsule()
                    .fill(Color.lightText)
                    .frame(width: max(0, proxy.size.width * CGFloat(value) / 100))
            }
        }
        .frame(height: 4)
    }
}

struct PendingUploadTileView: View {
    let wallpaper: Wallpaper

    private var displayURL: URL? {
        let raw = wallpaper.displayURL
        return raw.isEmpty ? nil : URL(string: raw)
    }

    private var title: String {
        wallpaper.title.isEmpty ? "Wallpaper \(wallpaper.id)" : wallpaper.title
    }

    private var statusText: String {
        switch wallpaper.status {
        case 0: "Processing"
        case 5: "Pending admin review"
        default: "Pending"
        }
    }

    private var statusSubtext: String {
        switch wallpaper.status {
        case 0: "Generating device variants"
        case 5: "Usually within a few hours"
        default: "Waiting for the next step"
        }
    }

    private var resolutionText: String? {
        guard wallpaper.width > 0, wallpaper.height > 0 else { return nil }
        return wallpaper.resolutionLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .overlay {
                    ZStack {
                        Color(hex: wallpaper.dominantColor ?? "#c8c2b8").opacity(0.58)
                        if let displayURL {
                            CachedAsyncImage(url: displayURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                placeholder
                            }
                        } else {
                            placeholder
                        }

                        if let resolutionText {
                            VStack {
                                HStack {
                                    Text(resolutionText)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .tracking(0.4)
                                        .foregroundStyle(Color(red: 0.20, green: 0.21, blue: 0.23))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.white.opacity(0.78)))
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(10)
                            .allowsHitTesting(false)
                        }

                        processingOverlay
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.hair, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)

            HStack(spacing: 8) {
                Text(statusBadge)
                    .font(.mono10)
                    .tracking(0.5)
                    .foregroundStyle(Color.muted)
                    .frame(width: 34, alignment: .leading)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        VStack(spacing: 7) {
            Image(systemName: wallpaper.fileType.hasPrefix("video/") ? "play.rectangle.fill" : "photo")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.lightText.opacity(0.78))
            Text(wallpaper.fileType.hasPrefix("video/") ? "VIDEO" : "IMAGE")
                .font(.mono10)
                .tracking(1.0)
                .foregroundStyle(Color.lightText.opacity(0.68))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingOverlay: some View {
        VStack(spacing: 10) {
            Text(statusText)
                .font(.mono10)
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.lightText)
            Text(statusSubtext)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.lightText.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.50), Color.black.opacity(0.70)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Stripes()
                    .stroke(Color.black.opacity(0.20), lineWidth: 8)
                    .blendMode(.overlay)
            }
        )
        .allowsHitTesting(false)
    }

    private var statusBadge: String {
        switch wallpaper.status {
        case 0: "PROC"
        case 5: "REV"
        default: "PEND"
        }
    }
}

private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 16
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}
