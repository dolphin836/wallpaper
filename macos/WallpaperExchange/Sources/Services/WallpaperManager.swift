import Foundation
import AppKit
import os.log

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

    // Console.app subsystem for setDesktopImageURL diagnostics. Useful for
    // chasing reports of "only the main screen got the new wallpaper" —
    // users can filter the unified log to com.wallpaperexchange.mac and
    // see per-screen success / failure for each rotation tick.
    private let logger = Logger(subsystem: "com.wallpaperexchange.mac", category: "wallpaper")
    private var rotationIntervalNs: UInt64 { UInt64(rotationInterval * 1_000_000_000) }

    // ID of the wallpaper most recently applied to the desktop, regardless
    // of how it got there (Set Wallpaper from the popover, Set & download,
    // or the rotation task). Drives the "Active" chip in the Downloaded
    // column. Persisted so the chip survives a relaunch.
    private(set) var currentWallpaperID: Int?
    private let currentWallpaperIDDefaultsKey = "wallpaper.currentID"

    let storageDir: URL

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

        // Re-apply the current wallpaper whenever the screen layout
        // changes (display connect / disconnect / wake-from-sleep) or
        // when the Mac itself wakes. NSScreen.screens skips sleeping or
        // disconnected displays, so a wallpaper applied during
        // auto-rotate while a secondary monitor was asleep would never
        // reach that display — when the user came back to a woken
        // monitor it still showed the old image. Two observers fix that
        // by re-running setDesktopImageURL on every screen as soon as
        // the topology stabilizes.
        installScreenChangeObservers()
    }

    // WallpaperManager is a singleton with process-lifetime — deinit
    // never runs, so we don't bother holding observer tokens to
    // unregister. NotificationCenter's block-based observers keep a
    // weak self capture so they're harmless if the singleton ever
    // were to disappear.

    private func installScreenChangeObservers() {
        // didChangeScreenParametersNotification fires for any display
        // topology change: connect, disconnect, mode change, and
        // (importantly) wake from display sleep.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reapplyCurrentWallpaper(source: "screen-change")
            }
        }
        // didWakeNotification fires when the Mac itself wakes from
        // system sleep. Some configurations (e.g. closed-lid clamshell
        // with the external display already on) only emit the
        // screen-change notification after the workspace wake, so
        // observing both gives us belt-and-suspenders coverage.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reapplyCurrentWallpaper(source: "system-wake")
            }
        }
    }

    /// Re-run setDesktopImageURL on every connected screen for the
    /// wallpaper currently marked as active. No-op when nothing is
    /// active or the file is missing locally.
    private func reapplyCurrentWallpaper(source: String) {
        guard let id = currentWallpaperID, let url = desktopURLForLocalWallpaper(id) else { return }
        applyToAllScreens(url: url, source: source)
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
            guard let url = desktopURLForLocalWallpaper(id) else { return nil }
            return (id, url)
        }
        guard let pick = pairs.randomElement() else { return }
        applyToAllScreens(url: pick.1, source: "auto-rotate")
        markCurrent(pick.0)
    }

    /// Set the same image URL on every connected NSScreen and log the
    /// per-screen result. The old code looped with `try?`, which made
    /// silent failures on secondary monitors impossible to diagnose
    /// (a user-reported issue: only the main display got the new
    /// wallpaper). We now log each screen's localized name + frame
    /// alongside the success / error and surface failures so the next
    /// rotation tick has something concrete to work from.
    private func applyToAllScreens(url: URL, source: String) {
        let screens = NSScreen.screens
        logger.info("applying wallpaper from \(source, privacy: .public): \(screens.count, privacy: .public) screen(s)")
        for (idx, screen) in screens.enumerated() {
            let name = screen.localizedName
            let frame = screen.frame
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ])
                logger.info("screen[\(idx, privacy: .public)] \(name, privacy: .public) \(Int(frame.width), privacy: .public)x\(Int(frame.height), privacy: .public): OK")
            } catch {
                logger.error("screen[\(idx, privacy: .public)] \(name, privacy: .public) \(Int(frame.width), privacy: .public)x\(Int(frame.height), privacy: .public): FAILED — \(error.localizedDescription, privacy: .public)")
            }
        }
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

    /// Largest pixel dimensions across all connected screens, accounting for
    /// retina scale. This is the resolution we ask the backend to size the
    /// download for — picking max(screen) lets the same file cover every
    /// display without anyone needing to upscale. Returns (0, 0) when there
    /// is no screen (unlikely, but better safe than asking for a 0×0 image).
    private static func maxScreenPixels() -> (Int, Int) {
        var maxW = 0
        var maxH = 0
        for screen in NSScreen.screens {
            let pixels = physicalPixels(for: screen)
            let w = pixels.width
            let h = pixels.height
            if w * h > maxW * maxH {
                maxW = w
                maxH = h
            }
        }
        return (maxW, maxH)
    }

    private static func physicalPixels(for screen: NSScreen) -> (width: Int, height: Int) {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            let width = CGDisplayPixelsWide(displayID)
            let height = CGDisplayPixelsHigh(displayID)
            if width > 0 && height > 0 {
                return (width, height)
            }
        }

        return (
            Int((screen.frame.width * screen.backingScaleFactor).rounded()),
            Int((screen.frame.height * screen.backingScaleFactor).rounded())
        )
    }

    func download(wallpaper: Wallpaper) async throws {
        let (tw, th) = Self.maxScreenPixels()
        try await download(wallpaper: wallpaper, targetWidth: tw, targetHeight: th)
    }

    func downloadOriginal(wallpaper: Wallpaper) async throws {
        try await download(wallpaper: wallpaper, targetWidth: 0, targetHeight: 0)
    }

    private func download(wallpaper: Wallpaper, targetWidth: Int, targetHeight: Int) async throws {
        if localURL(for: wallpaper.id) != nil {
            downloadedIDs.insert(wallpaper.id)
            return
        }
        guard !downloading.contains(wallpaper.id) else { return }
        downloading.insert(wallpaper.id)
        downloadProgress[wallpaper.id] = 0
        defer {
            downloading.remove(wallpaper.id)
            downloadProgress.removeValue(forKey: wallpaper.id)
        }

        let remoteURL = try await APIClient.shared.getDownloadURL(wallpaperID: wallpaper.id, targetWidth: targetWidth, targetHeight: targetHeight)

        let (tempURL, response) = try await Self.downloadWithProgress(from: remoteURL) { [weak self] p in
            self?.downloadProgress[wallpaper.id] = p
        }
        let ext = Self.fileExtension(from: response, url: remoteURL, fallback: wallpaper.fileType)
        let dest = storageDir.appendingPathComponent("\(wallpaper.id).\(ext)")

        try removeLocalFiles(for: wallpaper.id)
        try fm.moveItem(at: tempURL, to: dest)

        downloadedIDs.insert(wallpaper.id)
        recomputeTotalBytes()
    }

    private var fm: FileManager { FileManager.default }

    private func removeLocalFiles(for wallpaperID: Int) throws {
        let prefix = "\(wallpaperID)."
        guard let contents = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try fm.removeItem(at: url)
        }
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

    /// Apply the wallpaper to every connected display. Static images and Mac
    /// dynamic HEIC wallpapers use the local downloaded file directly. Video
    /// wallpapers cannot be passed to NSWorkspace as a desktop image, so the
    /// Mac client applies the poster/preview image while keeping the original
    /// video in the downloads folder.
    ///
    /// If the file is not yet on disk locally (e.g. the wallpaper was downloaded
    /// on another device — the "Downloaded" column is sourced from the server,
    /// not the local file scan), download it first. The backend's
    /// `HasDownloaded` check skips the coin charge when the user has already
    /// paid for this wallpaper, so re-fetching a previously-downloaded item from
    /// another device is free.
    func setAsWallpaper(_ wallpaper: Wallpaper) async throws {
        if Self.isVideo(wallpaper) {
            if localURL(for: wallpaper.id) == nil {
                try await download(wallpaper: wallpaper)
            }
            let poster = try await ensureVideoPoster(wallpaper)
            applyToAllScreens(url: poster, source: "manual-set-video id=\(wallpaper.id)")
            markCurrent(wallpaper.id)
            return
        }

        if localURL(for: wallpaper.id) == nil {
            try await download(wallpaper: wallpaper)
        }
        guard let url = localURL(for: wallpaper.id) else {
            throw WallpaperError.fileUnavailable
        }
        applyToAllScreens(url: url, source: "manual-set id=\(wallpaper.id)")
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
        removeVideoPosterFiles(for: wallpaperID)
        downloadedIDs.remove(wallpaperID)
        if currentWallpaperID == wallpaperID {
            currentWallpaperID = nil
            UserDefaults.standard.removeObject(forKey: currentWallpaperIDDefaultsKey)
        }
        recomputeTotalBytes()
    }

    /// Wipe every cached wallpaper from the downloads folder. The
    /// server-side download history is untouched — these files can be
    /// re-fetched on demand. Clears the current-wallpaper marker too.
    @discardableResult
    func clearDownloads() -> Int {
        let fm = FileManager.default
        var removed = 0
        if let contents = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) {
            for url in contents where (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        downloadedIDs.removeAll()
        currentWallpaperID = nil
        UserDefaults.standard.removeObject(forKey: currentWallpaperIDDefaultsKey)
        totalLocalBytes = 0
        return removed
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
            case "video/mp4": return "mp4"
            case "video/quicktime": return "mov"
            case "video/webm": return "webm"
            case "video/x-matroska": return "mkv"
            default: break
            }
        }

        let ft = fallback.lowercased()
        if ft.contains("heic") { return "heic" }
        if ft.contains("png") { return "png" }
        if ft.contains("webp") { return "webp" }
        if ft.contains("quicktime") || ft.contains("mov") { return "mov" }
        if ft.contains("webm") { return "webm" }
        if ft.contains("matroska") || ft.contains("mkv") { return "mkv" }
        if ft.contains("mp4") || ft.hasPrefix("video/") { return "mp4" }
        return "jpg"
    }

    private static func isVideo(_ wallpaper: Wallpaper) -> Bool {
        wallpaper.fileType.lowercased().hasPrefix("video/")
    }

    private static func isVideoFileURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "webm", "mkv":
            return true
        default:
            return false
        }
    }

    private func desktopURLForLocalWallpaper(_ wallpaperID: Int) -> URL? {
        guard let url = localURL(for: wallpaperID) else { return nil }
        if let poster = videoPosterURL(for: wallpaperID) {
            return poster
        }
        if Self.isVideoFileURL(url) {
            return nil
        }
        return url
    }

    private func videoPosterURL(for wallpaperID: Int) -> URL? {
        let prefix = "poster-\(wallpaperID)."
        guard let contents = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return nil }
        return contents.first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func removeVideoPosterFiles(for wallpaperID: Int) {
        let prefix = "poster-\(wallpaperID)."
        guard let contents = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: url)
        }
    }

    private func ensureVideoPoster(_ wallpaper: Wallpaper) async throws -> URL {
        if let existing = videoPosterURL(for: wallpaper.id) {
            return existing
        }

        let posterString = [wallpaper.previewURL, wallpaper.thumbURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let posterString, let remoteURL = URL(string: posterString) else {
            throw WallpaperError.fileUnavailable
        }

        let (tempURL, response) = try await Self.downloadWithProgress(from: remoteURL) { _ in }
        let ext = Self.fileExtension(from: response, url: remoteURL, fallback: "image/jpeg")
        let dest = storageDir.appendingPathComponent("poster-\(wallpaper.id).\(ext)")

        removeVideoPosterFiles(for: wallpaper.id)
        try fm.moveItem(at: tempURL, to: dest)
        recomputeTotalBytes()
        return dest
    }
}
