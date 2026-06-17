import Foundation
import AppKit
import os.log

enum WallpaperApplySurface: String, CaseIterable, Identifiable {
    case desktop
    case lockScreen
    case both

    var id: String { rawValue }
}

struct WallpaperDisplayTarget: Identifiable, Hashable {
    static let allID = "all"

    let id: String
    let name: String
    let detail: String
    let screenKey: String?
    let isMain: Bool

    var isAll: Bool { screenKey == nil }
}

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
    // and applies it on the user's chosen cadence. State is persisted across
    // launches via UserDefaults, so quitting + reopening the app preserves the
    // rotation.
    private(set) var autoRotate: Bool = false
    private(set) var autoRotateInterval: TimeInterval = WallpaperManager.defaultAutoRotateInterval
    // Absolute timestamp of the next rotation tick. Surfaced to the
    // ShuffleStatusBanner so it can render a live "NEXT · 2 H 34 M"
    // countdown. nil whenever autoRotate is off.
    private(set) var nextRotationAt: Date?
    private var rotationTask: Task<Void, Never>?
    private let autoRotateDefaultsKey = "wallpaper.autoRotate"
    private let autoRotateIntervalDefaultsKey = "wallpaper.autoRotate.interval"
    static let defaultAutoRotateInterval: TimeInterval = 4 * 3600
    static let minAutoRotateInterval: TimeInterval = 15 * 60
    static let maxAutoRotateInterval: TimeInterval = 7 * 24 * 3600

    // Console.app subsystem for setDesktopImageURL diagnostics. Useful for
    // chasing reports of "only the main screen got the new wallpaper" —
    // users can filter the unified log to com.wallpaperexchange.mac and
    // see per-screen success / failure for each rotation tick.
    private let logger = Logger(subsystem: "com.wallpaperexchange.mac", category: "wallpaper")
    private var rotationIntervalNs: UInt64 { UInt64(autoRotateInterval * 1_000_000_000) }

    // ID of the wallpaper most recently applied to the desktop, regardless
    // of whether it came from DetailPage or the rotation task. Drives the
    // "Active" chip in the Downloaded column and survives a relaunch.
    private(set) var currentWallpaperID: Int?
    private let currentWallpaperIDDefaultsKey = "wallpaper.currentID"
    private var currentWallpaperScreenKeys: Set<String>?

    let storageDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("WallpaperExchange/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        scanLocalFiles()

        // Resume rotation if the user had it on before quitting the app.
        let savedInterval = UserDefaults.standard.double(forKey: autoRotateIntervalDefaultsKey)
        autoRotateInterval = Self.sanitizedAutoRotateInterval(
            savedInterval > 0 ? savedInterval : Self.defaultAutoRotateInterval
        )
        autoRotate = UserDefaults.standard.bool(forKey: autoRotateDefaultsKey)
        let saved = UserDefaults.standard.integer(forKey: currentWallpaperIDDefaultsKey)
        currentWallpaperID = saved > 0 ? saved : nil
        if autoRotate {
            startRotation()
        }
        if !autoRotate, let savedID = currentWallpaperID, let savedURL = localURL(for: savedID),
           Self.isVideoFileURL(savedURL) {
            VideoWallpaperController.shared.start(videoURL: savedURL, wallpaperID: savedID)
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

    /// Re-run the current wallpaper on every connected screen. Static
    /// wallpapers use the system desktop API; video wallpapers rebuild the
    /// desktop-level AVPlayer windows for the current screen topology.
    private func reapplyCurrentWallpaper(source: String) {
        guard let id = currentWallpaperID, let url = localURL(for: id) else { return }
        let screens = screens(for: currentWallpaperScreenKeys)
        applyLocalWallpaper(id: id, url: url, source: source, screens: screens, markAsCurrent: false)
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

    func setAutoRotateInterval(_ interval: TimeInterval) {
        let sanitized = Self.sanitizedAutoRotateInterval(interval)
        guard abs(autoRotateInterval - sanitized) > 0.5 else { return }
        autoRotateInterval = sanitized
        UserDefaults.standard.set(sanitized, forKey: autoRotateIntervalDefaultsKey)
        if autoRotate {
            startRotation(applyImmediately: false)
        }
    }

    var autoRotateIntervalLabel: String {
        Self.formatAutoRotateInterval(autoRotateInterval)
    }

    static func sanitizedAutoRotateInterval(_ interval: TimeInterval) -> TimeInterval {
        min(max(interval, minAutoRotateInterval), maxAutoRotateInterval)
    }

    static func formatAutoRotateInterval(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((sanitizedAutoRotateInterval(interval) / 60).rounded()))
        if minutes < 60 {
            return L10n.manager.intervalMinutes(minutes)
        }

        if minutes % (24 * 60) == 0 {
            return L10n.manager.intervalDays(minutes / (24 * 60))
        }

        if minutes % 60 == 0 {
            return L10n.manager.intervalHours(minutes / 60)
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 {
            return L10n.manager.intervalMinutes(remainder)
        }
        return L10n.manager.intervalHoursMinutes(hours, remainder)
    }

    private func startRotation(applyImmediately: Bool = true) {
        stopRotation()
        // Apply once immediately when the user turns rotation on so the
        // setting feels active, then sleep between subsequent picks.
        // WallpaperManager is @MainActor so the Task inherits that isolation.
        nextRotationAt = Date().addingTimeInterval(autoRotateInterval)
        rotationTask = Task { [weak self] in
            guard let self else { return }
            if applyImmediately {
                self.applyRandomLocalWallpaper()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.rotationIntervalNs)
                guard !Task.isCancelled else { break }
                self.applyRandomLocalWallpaper()
                self.nextRotationAt = Date().addingTimeInterval(self.autoRotateInterval)
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
        applyLocalWallpaper(id: pick.0, url: pick.1, source: "auto-rotate")
    }

    /// Set the same image URL on every connected NSScreen and log the
    /// per-screen result. `System Events` is used as a best-effort second
    /// pass on multi-display setups because macOS can otherwise update
    /// only the primary display for the active Space.
    private func applyToAllScreens(
        url: URL,
        source: String,
        expectedWallpaperID: Int? = nil,
        scheduleDeferredSync: Bool = true
    ) {
        let screens = Self.connectedScreens()
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
        applyToEveryDesktopIfNeeded(url: url, screenCount: screens.count, source: source)
        scheduleDeferredScreenSyncIfNeeded(
            url: url,
            source: source,
            expectedWallpaperID: expectedWallpaperID,
            enabled: scheduleDeferredSync
        )
    }

    private static func connectedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        if !screens.isEmpty { return screens }
        if let main = NSScreen.main { return [main] }
        return []
    }

    static func displayTargets() -> [WallpaperDisplayTarget] {
        let screens = connectedScreens()
        let screenTargets = screens.enumerated().map { index, screen in
            let key = screenKey(screen) ?? "screen-\(index)"
            let pixels = displayModePixels(for: screen)
            let isMain = screen == NSScreen.main
            let mainLabel = isMain ? L10n.detail.wallpaperMainDisplay : L10n.detail.wallpaperSecondaryDisplay
            return WallpaperDisplayTarget(
                id: key,
                name: screen.localizedName,
                detail: "\(mainLabel) · \(pixels.width)×\(pixels.height)",
                screenKey: key,
                isMain: isMain
            )
        }
        return [
            WallpaperDisplayTarget(
                id: WallpaperDisplayTarget.allID,
                name: L10n.detail.wallpaperAllDisplays,
                detail: L10n.detail.wallpaperAllDisplaysDetail(screens.count),
                screenKey: nil,
                isMain: false
            ),
        ] + screenTargets
    }

    private static func screenKey(_ screen: NSScreen) -> String? {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func applyToEveryDesktopIfNeeded(url: URL, screenCount: Int, source: String) {
        guard screenCount > 1 else { return }
        let script = """
        tell application "System Events"
            repeat with currentDesktop in desktops
                set picture of currentDesktop to "\(Self.appleScriptString(url.path))"
            end repeat
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logger.info("system-events desktop sync from \(source, privacy: .public): OK")
            } else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                logger.error("system-events desktop sync from \(source, privacy: .public): FAILED — \(message, privacy: .public)")
            }
        } catch {
            logger.error("system-events desktop sync from \(source, privacy: .public): FAILED — \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleDeferredScreenSyncIfNeeded(
        url: URL,
        source: String,
        expectedWallpaperID: Int?,
        enabled: Bool
    ) {
        guard enabled, Self.connectedScreens().count > 1 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            if let expectedWallpaperID, self.currentWallpaperID != expectedWallpaperID {
                return
            }
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            self.applyToAllScreens(
                url: url,
                source: "\(source)-settle",
                expectedWallpaperID: expectedWallpaperID,
                scheduleDeferredSync: false
            )
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func screens(for keys: Set<String>?) -> [NSScreen] {
        let screens = Self.connectedScreens()
        guard let keys, !keys.isEmpty else { return screens }
        let filtered = screens.filter { screen in
            guard let key = Self.screenKey(screen) else { return false }
            return keys.contains(key)
        }
        return filtered.isEmpty ? screens : filtered
    }

    private func screens(for target: WallpaperDisplayTarget) -> [NSScreen] {
        guard let key = target.screenKey else { return Self.connectedScreens() }
        return screens(for: Set([key]))
    }

    private func applyLocalWallpaper(
        id: Int,
        url: URL,
        source: String,
        screens: [NSScreen]? = nil,
        markAsCurrent: Bool = true
    ) {
        let targetScreens = screens ?? Self.connectedScreens()
        if Self.isVideoFileURL(url) {
            logger.info("applying video wallpaper from \(source, privacy: .public): id=\(id, privacy: .public)")
            VideoWallpaperController.shared.start(videoURL: url, wallpaperID: id, screens: targetScreens)
            if markAsCurrent {
                markCurrent(id, screens: targetScreens)
            }
            return
        }

        VideoWallpaperController.shared.stop()
        applyToScreens(url: url, screens: targetScreens, source: source, expectedWallpaperID: id)
        if markAsCurrent {
            markCurrent(id, screens: targetScreens)
        }
    }

    private func applyToScreens(
        url: URL,
        screens: [NSScreen],
        source: String,
        expectedWallpaperID: Int? = nil
    ) {
        let allScreens = Self.connectedScreens()
        let targets = screens.isEmpty ? allScreens : screens
        logger.info("applying wallpaper from \(source, privacy: .public): \(targets.count, privacy: .public) selected screen(s)")
        for (idx, screen) in targets.enumerated() {
            let name = screen.localizedName
            let frame = screen.frame
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ])
                logger.info("target[\(idx, privacy: .public)] \(name, privacy: .public) \(Int(frame.width), privacy: .public)x\(Int(frame.height), privacy: .public): OK")
            } catch {
                logger.error("target[\(idx, privacy: .public)] \(name, privacy: .public) \(Int(frame.width), privacy: .public)x\(Int(frame.height), privacy: .public): FAILED — \(error.localizedDescription, privacy: .public)")
            }
        }

        let isAllScreens = Set(targets.compactMap(Self.screenKey)) == Set(allScreens.compactMap(Self.screenKey))
        if isAllScreens {
            applyToEveryDesktopIfNeeded(url: url, screenCount: allScreens.count, source: source)
            scheduleDeferredScreenSyncIfNeeded(
                url: url,
                source: source,
                expectedWallpaperID: expectedWallpaperID,
                enabled: true
            )
        }
    }

    var storagePath: URL { storageDir }

    func isDownloaded(_ wallpaperID: Int) -> Bool {
        localURL(for: wallpaperID) != nil
    }

    func localURL(for wallpaperID: Int) -> URL? {
        let fm = FileManager.default
        let prefix = "\(wallpaperID)."
        guard let contents = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return nil }
        return contents.first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Largest current display-mode dimensions across all connected screens.
    /// This follows the same "looks like" resolution used for compatibility
    /// filtering, so a display scaled to 1920 asks for a 1920-covering variant
    /// rather than a native-panel-sized one. Returns (0, 0) when there is no
    /// screen (unlikely, but better safe than asking for a 0x0 image).
    private static func maxScreenPixels() -> (Int, Int) {
        var maxW = 0
        var maxH = 0
        for screen in NSScreen.screens {
            let pixels = displayModePixels(for: screen)
            let w = pixels.width
            let h = pixels.height
            if w * h > maxW * maxH {
                maxW = w
                maxH = h
            }
        }
        return (maxW, maxH)
    }

    private static func displayModePixels(for screen: NSScreen) -> (width: Int, height: Int) {
        return (
            Int(screen.frame.width.rounded()),
            Int(screen.frame.height.rounded())
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
        if let existing = localURL(for: wallpaper.id) {
            if !Self.isVideo(wallpaper) || Self.isVideoFileURL(existing) {
                downloadedIDs.insert(wallpaper.id)
                return
            }
            try removeLocalFiles(for: wallpaper.id)
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
        case lockScreenUnavailable

        var errorDescription: String? {
            switch self {
            case .fileUnavailable: return L10n.manager.fileUnavailable
            case .lockScreenUnavailable: return L10n.detail.lockScreenUnavailable
            }
        }
    }

    /// Apply the wallpaper to every connected display. Static images and Mac
    /// dynamic HEIC wallpapers use the system desktop API. Video wallpapers
    /// use a desktop-level AVPlayer window per screen, with the poster image
    /// also set as a fallback for app quit / playback interruption.
    ///
    /// If the file is not yet on disk locally (e.g. the wallpaper was downloaded
    /// on another device — the "Downloaded" column is sourced from the server,
    /// not the local file scan), download it first. The backend's
    /// `HasDownloaded` check skips the coin charge when the user has already
    /// paid for this wallpaper, so re-fetching a previously-downloaded item from
    /// another device is free.
    func setAsWallpaper(_ wallpaper: Wallpaper) async throws {
        try await setAsWallpaper(
            wallpaper,
            target: WallpaperDisplayTarget(
                id: WallpaperDisplayTarget.allID,
                name: L10n.detail.wallpaperAllDisplays,
                detail: L10n.detail.wallpaperAllDisplaysDetail(Self.connectedScreens().count),
                screenKey: nil,
                isMain: false
            ),
            surface: .desktop
        )
    }

    func setAsWallpaper(_ wallpaper: Wallpaper, target: WallpaperDisplayTarget, surface: WallpaperApplySurface) async throws {
        if Self.isVideo(wallpaper), surface != .desktop {
            throw WallpaperError.lockScreenUnavailable
        }

        if Self.isVideo(wallpaper) {
            let videoURL = try await ensureLocalVideo(wallpaper)
            if let poster = try? await ensureVideoPoster(wallpaper) {
                applyToScreens(
                    url: poster,
                    screens: screens(for: target),
                    source: "video-poster id=\(wallpaper.id)",
                    expectedWallpaperID: target.isAll ? wallpaper.id : nil
                )
            }
            VideoWallpaperController.shared.start(videoURL: videoURL, wallpaperID: wallpaper.id, screens: screens(for: target))
            if target.isAll {
                markCurrent(wallpaper.id, screens: screens(for: target))
            }
            return
        }

        if localURL(for: wallpaper.id) == nil {
            try await download(wallpaper: wallpaper)
        }
        guard let url = localURL(for: wallpaper.id) else {
            throw WallpaperError.fileUnavailable
        }
        let targetScreens = screens(for: target)
        switch surface {
        case .desktop:
            applyLocalWallpaper(
                id: wallpaper.id,
                url: url,
                source: "manual-set id=\(wallpaper.id)",
                screens: targetScreens,
                markAsCurrent: target.isAll
            )
        case .lockScreen:
            try applyLockScreenImage(url: url, source: "manual-lock id=\(wallpaper.id)")
        case .both:
            applyLocalWallpaper(
                id: wallpaper.id,
                url: url,
                source: "manual-set id=\(wallpaper.id)",
                screens: targetScreens,
                markAsCurrent: target.isAll
            )
            try applyLockScreenImage(url: url, source: "manual-lock id=\(wallpaper.id)")
        }
    }

    // Record the wallpaper id that is currently on the desktop. Drives the
    // Active chip on the corresponding tile and survives a relaunch via
    // UserDefaults.
    private func markCurrent(_ id: Int, screens: [NSScreen]? = nil) {
        currentWallpaperID = id
        currentWallpaperScreenKeys = screens.map { Set($0.compactMap(Self.screenKey)) }
        UserDefaults.standard.set(id, forKey: currentWallpaperIDDefaultsKey)
    }

    private func applyLockScreenImage(url: URL, source: String) throws {
        // macOS does not expose a public AppKit API for an independent
        // lock-screen wallpaper. The wallpaper agent reads this system
        // preference for its global wallpaper source, so we update it as a
        // best-effort lock-screen sync while keeping the desktop path on the
        // supported NSWorkspace API above.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.wallpaper", "SystemWallpaperURL", "-string", url.absoluteString]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                logger.error("lock-screen sync from \(source, privacy: .public): FAILED — \(message, privacy: .public)")
                throw WallpaperError.lockScreenUnavailable
            }
            logger.info("lock-screen sync from \(source, privacy: .public): OK")
        } catch {
            logger.error("lock-screen sync from \(source, privacy: .public): FAILED — \(error.localizedDescription, privacy: .public)")
            throw WallpaperError.lockScreenUnavailable
        }
    }

    func deleteLocal(_ wallpaperID: Int) {
        if let url = localURL(for: wallpaperID) {
            try? FileManager.default.removeItem(at: url)
        }
        removeVideoPosterFiles(for: wallpaperID)
        downloadedIDs.remove(wallpaperID)
        if currentWallpaperID == wallpaperID {
            VideoWallpaperController.shared.stopIfActive(wallpaperID: wallpaperID)
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
        VideoWallpaperController.shared.stop()
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

    private func ensureLocalVideo(_ wallpaper: Wallpaper) async throws -> URL {
        if let existing = localURL(for: wallpaper.id), Self.isVideoFileURL(existing) {
            return existing
        }
        if localURL(for: wallpaper.id) != nil {
            try removeLocalFiles(for: wallpaper.id)
        }
        try await download(wallpaper: wallpaper, targetWidth: 0, targetHeight: 0)
        guard let url = localURL(for: wallpaper.id), Self.isVideoFileURL(url) else {
            throw WallpaperError.fileUnavailable
        }
        return url
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
