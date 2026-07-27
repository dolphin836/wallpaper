import Foundation
import AppKit
import AVFoundation
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
    private(set) var autoRotateCollectionID: Int?
    private(set) var autoRotateCollectionTitle: String?
    // Absolute timestamp of the next rotation tick. Surfaced to the
    // ShuffleStatusBanner so it can render a live "NEXT · 2 H 34 M"
    // countdown. nil whenever autoRotate is off.
    private(set) var nextRotationAt: Date?
    private var rotationTask: Task<Void, Never>?
    private let autoRotateDefaultsKey = "wallpaper.autoRotate"
    private let autoRotateIntervalDefaultsKey = "wallpaper.autoRotate.interval"
    private let autoRotateCollectionIDDefaultsKey = "wallpaper.autoRotate.collectionID"
    private let autoRotateCollectionTitleDefaultsKey = "wallpaper.autoRotate.collectionTitle"
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
        let savedCollectionID = UserDefaults.standard.integer(forKey: autoRotateCollectionIDDefaultsKey)
        autoRotateCollectionID = savedCollectionID > 0 ? savedCollectionID : nil
        autoRotateCollectionTitle = UserDefaults.standard.string(forKey: autoRotateCollectionTitleDefaultsKey)
        let saved = UserDefaults.standard.integer(forKey: currentWallpaperIDDefaultsKey)
        currentWallpaperID = saved > 0 ? saved : nil
        // A video wallpaper is an in-process desktop window, so macOS falls
        // back to its poster as soon as the app exits. Restore that saved
        // video from local storage on every launch, independently of whether
        // auto-rotate is enabled or the network is ready yet.
        if let savedID = currentWallpaperID, let savedURL = localURL(for: savedID),
           Self.isVideoFileURL(savedURL) {
            applyLocalWallpaper(
                id: savedID,
                url: savedURL,
                source: "app-launch restore",
                markAsCurrent: false
            )
        }
        if autoRotate {
            // Resuming the scheduler should preserve the currently selected
            // wallpaper until the next interval. An immediate server-backed
            // pick is fragile during login, before networking is available.
            startRotation(applyImmediately: false)
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
        if AerialLockScreenService.isSupported {
            _ = AerialLockScreenService.shared
        }
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

    func clearAutoRotateCollection() {
        autoRotateCollectionID = nil
        autoRotateCollectionTitle = nil
        UserDefaults.standard.removeObject(forKey: autoRotateCollectionIDDefaultsKey)
        UserDefaults.standard.removeObject(forKey: autoRotateCollectionTitleDefaultsKey)
        if autoRotate {
            startRotation(applyImmediately: false)
        }
    }

    func fetchAllCollectionWallpapers(collectionID: Int) async throws -> [Wallpaper] {
        var items: [Wallpaper] = []
        var cursor: Int?
        var seenCursors: Set<Int> = []

        while true {
            let data = try await APIClient.shared.fetchCollectionWallpapers(
                collectionID: collectionID,
                cursor: cursor,
                limit: 100
            )
            items.append(contentsOf: data.items)

            guard data.hasMore, let nextCursor = data.nextCursor, nextCursor > 0 else {
                break
            }
            guard seenCursors.insert(nextCursor).inserted else {
                break
            }
            cursor = nextCursor
        }

        return items
    }

    func missingLocalWallpapers(in wallpapers: [Wallpaper]) -> [Wallpaper] {
        wallpapers.filter { !isDownloaded($0.id) }
    }

    func setAutoRotateCollection(
        _ collection: CollectionItem,
        wallpapers: [Wallpaper],
        downloadMissing: Bool
    ) async throws {
        guard !wallpapers.isEmpty else {
            throw WallpaperError.autoRotateCollectionEmpty
        }

        if downloadMissing {
            for wallpaper in wallpapers where !isDownloaded(wallpaper.id) {
                try await download(wallpaper: wallpaper)
            }
        }

        autoRotateCollectionID = collection.id
        autoRotateCollectionTitle = collection.title
        UserDefaults.standard.set(collection.id, forKey: autoRotateCollectionIDDefaultsKey)
        UserDefaults.standard.set(collection.title, forKey: autoRotateCollectionTitleDefaultsKey)

        if autoRotate {
            startRotation()
        } else {
            setAutoRotate(true)
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
                await self.applyNextAutoRotateWallpaper()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.rotationIntervalNs)
                guard !Task.isCancelled else { break }
                await self.applyNextAutoRotateWallpaper()
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

    private func applyNextAutoRotateWallpaper() async {
        if let collectionID = autoRotateCollectionID {
            await applyRandomCollectionWallpaper(collectionID: collectionID)
        } else {
            applyRandomLocalWallpaper()
        }
    }

    private func applyRandomCollectionWallpaper(collectionID: Int) async {
        do {
            let wallpapers = try await fetchAllCollectionWallpapers(collectionID: collectionID)
            let pairs: [(Int, URL)] = wallpapers.compactMap { wallpaper in
                guard let url = localURL(for: wallpaper.id) else { return nil }
                return (wallpaper.id, url)
            }
            guard let pick = pairs.randomElement() else {
                logger.info("auto-rotate collection \(collectionID, privacy: .public): no local wallpapers available")
                return
            }
            applyLocalWallpaper(id: pick.0, url: pick.1, source: "auto-rotate collection=\(collectionID)")
        } catch {
            logger.error("auto-rotate collection \(collectionID, privacy: .public): failed — \(error.localizedDescription, privacy: .public)")
        }
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

        VideoWallpaperController.shared.stop(screens: targetScreens)
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

    private static func displayModePixels(for screen: NSScreen) -> (width: Int, height: Int) {
        return (
            Int(screen.frame.width.rounded()),
            Int(screen.frame.height.rounded())
        )
    }

    // Downloads always fetch the original file (2026-07-05 decision:
    // device variants are gone — clients filter non-fitting wallpapers
    // instead of receiving resized copies). downloadOriginal remains as
    // an alias for existing call sites.
    func download(wallpaper: Wallpaper) async throws {
        try await performDownload(wallpaper: wallpaper, cachedOriginalKey: nil)
    }

    func downloadOriginal(wallpaper: Wallpaper, cachedOriginalKey: String? = nil) async throws {
        try await performDownload(wallpaper: wallpaper, cachedOriginalKey: cachedOriginalKey)
    }

    private func performDownload(wallpaper: Wallpaper, cachedOriginalKey: String?) async throws {
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

        // The API call stays mandatory — it charges the coin and counts
        // the download; only the file transfer below is skippable.
        let remoteURL = try await APIClient.shared.getDownloadURL(wallpaperID: wallpaper.id)

        // If the image pipeline already fetched these exact bytes, reuse the
        // versioned original cache entry. The download URL has a different
        // short-lived signature, so keying this lookup by URL would miss.
        if let cachedOriginalKey,
           let cached = await ImageCacheStore.shared.cachedData(forKey: cachedOriginalKey) {
            let ext = Self.fileExtension(from: nil, url: remoteURL, fallback: wallpaper.fileType)
            let dest = storageDir.appendingPathComponent("\(wallpaper.id).\(ext)")
            try removeLocalFiles(for: wallpaper.id)
            try cached.write(to: dest, options: .atomic)
            downloadProgress[wallpaper.id] = 1
            downloadedIDs.insert(wallpaper.id)
            recomputeTotalBytes()
            return
        }

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
        case autoRotateCollectionEmpty

        var errorDescription: String? {
            switch self {
            case .fileUnavailable: return L10n.manager.fileUnavailable
            case .lockScreenUnavailable: return L10n.detail.lockScreenUnavailable
            case .autoRotateCollectionEmpty: return L10n.manager.autoRotateCollectionEmpty
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
        if Self.isVideo(wallpaper) {
            let videoURL = try await ensureLocalVideo(wallpaper)
            let poster = try? await ensureVideoPoster(wallpaper)

            if surface == .desktop || surface == .both {
                applyVideoDesktopWallpaper(wallpaper, videoURL: videoURL, poster: poster, target: target)
            }
            if surface == .lockScreen || surface == .both {
                try await AerialLockScreenService.shared.apply(
                    wallpaper: wallpaper,
                    sourceURL: videoURL,
                    sourceIsVideo: true,
                    linkDesktop: surface == .both
                )
            }
            return
        }

        if localURL(for: wallpaper.id) == nil {
            try await download(wallpaper: wallpaper)
        }
        guard let url = localURL(for: wallpaper.id) else {
            throw WallpaperError.fileUnavailable
        }

        if surface == .desktop || surface == .both {
            let targetScreens = screens(for: target)
            applyLocalWallpaper(
                id: wallpaper.id,
                url: url,
                source: "manual-set id=\(wallpaper.id)",
                screens: targetScreens,
                markAsCurrent: target.isAll
            )
        }
        if surface == .lockScreen || surface == .both {
            try await AerialLockScreenService.shared.apply(
                wallpaper: wallpaper,
                sourceURL: url,
                sourceIsVideo: false,
                linkDesktop: false
            )
        }

    }

    private func applyVideoDesktopWallpaper(_ wallpaper: Wallpaper, videoURL: URL, poster: URL?, target: WallpaperDisplayTarget) {
        let targetScreens = screens(for: target)
        if let poster {
            applyToScreens(
                url: poster,
                screens: targetScreens,
                source: "video-poster id=\(wallpaper.id)",
                expectedWallpaperID: target.isAll ? wallpaper.id : nil
            )
        }
        VideoWallpaperController.shared.start(videoURL: videoURL, wallpaperID: wallpaper.id, screens: targetScreens)
        if target.isAll {
            markCurrent(wallpaper.id, screens: targetScreens)
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

    private static func fileExtension(from response: URLResponse?, url: URL, fallback: String) -> String {
        let pathExt = url.pathExtension.lowercased()
        if !pathExt.isEmpty, pathExt.count <= 5 { return pathExt }

        if let mime = response?.mimeType {
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
        try await performDownload(wallpaper: wallpaper, cachedOriginalKey: nil)
        guard let url = localURL(for: wallpaper.id), Self.isVideoFileURL(url) else {
            throw WallpaperError.fileUnavailable
        }
        return url
    }

    private func ensureVideoPoster(_ wallpaper: Wallpaper) async throws -> URL {
        if let existing = videoPosterURL(for: wallpaper.id) {
            return existing
        }

        // A video that is already in the app's Downloads folder is a complete
        // local resource. Generate its desktop fallback poster from the local
        // movie first so "Set as wallpaper" never needs the network merely to
        // rebuild chrome around an existing download.
        if let localVideo = localURL(for: wallpaper.id),
           Self.isVideoFileURL(localVideo),
           let posterData = await Self.makeVideoPosterData(from: localVideo) {
            let dest = storageDir.appendingPathComponent("poster-\(wallpaper.id).jpg")
            removeVideoPosterFiles(for: wallpaper.id)
            try posterData.write(to: dest, options: .atomic)
            recomputeTotalBytes()
            return dest
        }

        let posterString = [wallpaper.previewURL, wallpaper.thumbURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let posterString, let remoteURL = URL(string: posterString) else {
            throw WallpaperError.fileUnavailable
        }

        // The detail preview normally fetched these bytes already. Reuse that
        // disk-cache entry before falling back to a new poster transfer.
        if let cachedPoster = await ImageCacheStore.shared.cachedData(for: remoteURL) {
            let ext = Self.fileExtension(from: nil, url: remoteURL, fallback: "image/jpeg")
            let dest = storageDir.appendingPathComponent("poster-\(wallpaper.id).\(ext)")
            removeVideoPosterFiles(for: wallpaper.id)
            try cachedPoster.write(to: dest, options: .atomic)
            recomputeTotalBytes()
            return dest
        }

        let (tempURL, response) = try await Self.downloadWithProgress(from: remoteURL) { _ in }
        let ext = Self.fileExtension(from: response, url: remoteURL, fallback: "image/jpeg")
        let dest = storageDir.appendingPathComponent("poster-\(wallpaper.id).\(ext)")

        removeVideoPosterFiles(for: wallpaper.id)
        try fm.moveItem(at: tempURL, to: dest)
        recomputeTotalBytes()
        return dest
    }

    nonisolated private static func makeVideoPosterData(from videoURL: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = NSSize(width: 2560, height: 2560)
            let time = CMTime(seconds: 0.25, preferredTimescale: 600)

            do {
                let result = try await generator.image(at: time)
                return NSBitmapImageRep(cgImage: result.image).representation(
                    using: .jpeg,
                    properties: [.compressionFactor: 0.9]
                )
            } catch {
                return nil
            }
        }.value
    }
}
