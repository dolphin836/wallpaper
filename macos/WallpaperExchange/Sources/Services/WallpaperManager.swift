import Foundation
import AppKit

@MainActor
@Observable
final class WallpaperManager {
    static let shared = WallpaperManager()

    private(set) var downloadedIDs: Set<Int> = []
    private(set) var downloading: Set<Int> = []
    // 0.0 → 1.0 per wallpaper currently being fetched. Populated only after the
    // first KVO callback from URLSessionDownloadTask fires, so dynamic
    // wallpapers (large multi-frame HEIC files) get a real progress bar
    // instead of an indeterminate spinner. Cleared on completion/failure.
    private(set) var downloadProgress: [Int: Double] = [:]

    // When true, a background task picks a random locally-downloaded wallpaper
    // and applies it every 4 hours. State is persisted across launches via
    // UserDefaults, so quitting + reopening the app preserves the rotation.
    private(set) var autoRotate: Bool = false
    // Absolute timestamp of the next rotation tick. Surfaced to the
    // ShuffleStatusBanner so it can render a live "NEXT · 2 H 34 M"
    // countdown. nil whenever autoRotate is off.
    private(set) var nextRotationAt: Date?
    private var rotationTask: Task<Void, Never>?
    private let autoRotateDefaultsKey = "wallpaper.autoRotate"
    private let rotationInterval: TimeInterval = 4 * 3600
    private var rotationIntervalNs: UInt64 { UInt64(rotationInterval * 1_000_000_000) }

    // ID of the wallpaper most recently applied to the desktop, regardless
    // of how it got there (Set Wallpaper from the popover, Set & download,
    // or the rotation task). Drives the "Active" chip in the Downloaded
    // column. Persisted so the chip survives a relaunch.
    private(set) var currentWallpaperID: Int?
    private let currentWallpaperIDDefaultsKey = "wallpaper.currentID"

    private let storageDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("WallpaperExchange/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        scanLocalFiles()

        // Resume rotation if the user had it on before quitting the app.
        autoRotate = UserDefaults.standard.bool(forKey: autoRotateDefaultsKey)
        let saved = UserDefaults.standard.integer(forKey: currentWallpaperIDDefaultsKey)
        currentWallpaperID = saved > 0 ? saved : nil
        if autoRotate {
            startRotation()
        }
    }

    // MARK: - Auto-rotate

    func setAutoRotate(_ enabled: Bool) {
        guard autoRotate != enabled else { return }
        autoRotate = enabled
        UserDefaults.standard.set(enabled, forKey: autoRotateDefaultsKey)
        if enabled {
            startRotation()
        } else {
            stopRotation()
        }
    }

    private func startRotation() {
        stopRotation()
        // Apply once immediately so the user sees the rotation took effect,
        // then sleep 4h between subsequent picks. WallpaperManager is
        // @MainActor so the Task inherits that isolation.
        nextRotationAt = Date().addingTimeInterval(rotationInterval)
        rotationTask = Task { [weak self] in
            guard let self else { return }
            self.applyRandomLocalWallpaper()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.rotationIntervalNs)
                guard !Task.isCancelled else { break }
                self.applyRandomLocalWallpaper()
                self.nextRotationAt = Date().addingTimeInterval(self.rotationInterval)
            }
        }
    }

    private func stopRotation() {
        rotationTask?.cancel()
        rotationTask = nil
        nextRotationAt = nil
    }

    /// Pick one of the locally-stored wallpaper files at random and apply it.
    /// Server-only records (downloaded on another device but never pulled to
    /// this Mac) are excluded — caller asked specifically that "没有下载到本地
    /// 的不管". Silent no-op when nothing is available locally; the rotation
    /// task keeps running so the next firing will pick up newly-downloaded
    /// files automatically.
    private func applyRandomLocalWallpaper() {
        // Pair each candidate URL with its wallpaper id so we can update
        // currentWallpaperID after applying — the rotation tile should
        // show the same Active chip as a manual Set Wallpaper does.
        let pairs: [(Int, URL)] = downloadedIDs.compactMap { id in
            guard let url = localURL(for: id) else { return nil }
            return (id, url)
        }
        guard let pick = pairs.randomElement() else { return }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(pick.1, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
        markCurrent(pick.0)
    }

    var storagePath: URL { storageDir }

    func isDownloaded(_ wallpaperID: Int) -> Bool {
        downloadedIDs.contains(wallpaperID)
    }

    func localURL(for wallpaperID: Int) -> URL? {
        let fm = FileManager.default
        let prefix = "\(wallpaperID)."
        guard let contents = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return nil }
        return contents.first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    func download(wallpaper: Wallpaper) async throws {
        guard !downloading.contains(wallpaper.id) else { return }
        downloading.insert(wallpaper.id)
        downloadProgress[wallpaper.id] = 0
        defer {
            downloading.remove(wallpaper.id)
            downloadProgress.removeValue(forKey: wallpaper.id)
        }

        let remoteURL = try await APIClient.shared.getDownloadURL(wallpaperID: wallpaper.id)

        let (tempURL, response) = try await Self.downloadWithProgress(from: remoteURL) { [weak self] p in
            self?.downloadProgress[wallpaper.id] = p
        }
        let ext = Self.fileExtension(from: response, url: remoteURL, fallback: wallpaper.fileType)
        let dest = storageDir.appendingPathComponent("\(wallpaper.id).\(ext)")

        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempURL, to: dest)

        downloadedIDs.insert(wallpaper.id)
        recomputeTotalBytes()
    }

    // Wraps URLSessionDownloadTask in async/await with progress reporting via KVO
    // on task.progress.fractionCompleted. The async URLSession.download(from:) API
    // doesn't expose progress; this is the standard workaround.
    //
    // The system deletes the temp file when the completion handler returns, so we
    // immediately move it to a UUID-named temp location we control and hand that
    // URL back to the caller — caller is responsible for moving it to its final
    // destination.
    private static func downloadWithProgress(
        from url: URL,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        // Box the observation so it survives until the completion handler runs.
        // The closure-captured `holder` keeps it alive for the task's lifetime.
        // `@unchecked Sendable` is safe here: we only write `observation` once
        // before `task.resume()` and clear it once inside the completion handler,
        // so there's no concurrent mutation in practice.
        final class Holder: @unchecked Sendable { var observation: NSKeyValueObservation? }
        let holder = Holder()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                holder.observation?.invalidate()
                holder.observation = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL, let response else {
                    continuation.resume(throwing: URLError(.unknown))
                    return
                }
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: keep)
                    continuation.resume(returning: (keep, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            holder.observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let p = progress.fractionCompleted
                Task { @MainActor in onProgress(p) }
            }
            task.resume()
        }
    }

    enum WallpaperError: LocalizedError {
        case fileUnavailable
        var errorDescription: String? {
            switch self {
            case .fileUnavailable: return "Wallpaper file is not available locally."
            }
        }
    }

    /// Apply the wallpaper to every connected display. If the file is not yet on
    /// disk locally (e.g. the wallpaper was downloaded on another device — the
    /// "Downloaded" column is sourced from the server, not the local file scan),
    /// download it first. The backend's `HasDownloaded` check skips the coin
    /// charge when the user has already paid for this wallpaper, so re-fetching
    /// a previously-downloaded item from another device is free.
    func setAsWallpaper(_ wallpaper: Wallpaper) async throws {
        if localURL(for: wallpaper.id) == nil {
            try await download(wallpaper: wallpaper)
        }
        guard let url = localURL(for: wallpaper.id) else {
            throw WallpaperError.fileUnavailable
        }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
        markCurrent(wallpaper.id)
    }

    // Record the wallpaper id that is currently on the desktop. Drives the
    // Active chip on the corresponding tile and survives a relaunch via
    // UserDefaults.
    private func markCurrent(_ id: Int) {
        currentWallpaperID = id
        UserDefaults.standard.set(id, forKey: currentWallpaperIDDefaultsKey)
    }

    func deleteLocal(_ wallpaperID: Int) {
        if let url = localURL(for: wallpaperID) {
            try? FileManager.default.removeItem(at: url)
        }
        downloadedIDs.remove(wallpaperID)
        if currentWallpaperID == wallpaperID {
            currentWallpaperID = nil
            UserDefaults.standard.removeObject(forKey: currentWallpaperIDDefaultsKey)
        }
        recomputeTotalBytes()
    }

    // Total size in bytes of every file in the downloads folder. Surfaced
    // to the popover footer so the user can see at a glance how much disk
    // the cached wallpapers are using. Recomputed whenever the local set
    // changes — after download, deleteLocal, and on startup.
    private(set) var totalLocalBytes: Int64 = 0

    private func scanLocalFiles() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        var bytes: Int64 = 0
        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = Int(name) {
                downloadedIDs.insert(id)
            }
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                bytes += Int64(size)
            }
        }
        totalLocalBytes = bytes
    }

    // Lighter than scanLocalFiles — just re-tally the on-disk size without
    // rebuilding downloadedIDs. Use after a single download/delete so the
    // footer reflects the new total without re-scanning every filename.
    private func recomputeTotalBytes() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            totalLocalBytes = 0
            return
        }
        var bytes: Int64 = 0
        for url in contents {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                bytes += Int64(size)
            }
        }
        totalLocalBytes = bytes
    }

    private static func fileExtension(from response: URLResponse, url: URL, fallback: String) -> String {
        let pathExt = url.pathExtension.lowercased()
        if !pathExt.isEmpty, pathExt.count <= 5 { return pathExt }

        if let mime = response.mimeType {
            switch mime {
            case "image/jpeg": return "jpg"
            case "image/png": return "png"
            case "image/heic", "image/heif": return "heic"
            case "image/webp": return "webp"
            default: break
            }
        }

        let ft = fallback.lowercased()
        if ft.contains("heic") { return "heic" }
        if ft.contains("png") { return "png" }
        if ft.contains("webp") { return "webp" }
        return "jpg"
    }
}
