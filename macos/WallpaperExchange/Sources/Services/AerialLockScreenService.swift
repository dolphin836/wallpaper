import AppKit
import AVFoundation
import CoreFoundation
import CoreVideo
import Foundation
import os.log
import VideoToolbox

/// macOS 26 does not expose a public lock-screen wallpaper API. Its lock screen
/// is rendered by the selected Apple Aerial asset, so the app safely replaces
/// the already-selected, already-downloaded Aerial movie in-place. The original
/// movie is backed up before the first replacement and can be restored from
/// Settings at any time.
@MainActor
final class AerialLockScreenService {
    static let shared = AerialLockScreenService()

    static var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    enum AerialError: LocalizedError {
        case unsupported
        case storeUnavailable
        case noAerialSelected
        case aerialVideoMissing
        case permissionRequired
        case imageUnavailable
        case exportUnavailable
        case conversionFailed(String)
        case screenSaverConfigurationFailed
        case reloadFailed
        case restoreUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return L10n.detail.lockScreenUnavailable
            case .storeUnavailable:
                return L10n.detail.lockScreenStoreUnavailable
            case .noAerialSelected:
                return L10n.detail.lockScreenAerialRequired
            case .aerialVideoMissing:
                return L10n.detail.lockScreenAerialDownloadRequired
            case .permissionRequired:
                return L10n.detail.lockScreenPermissionRequired
            case .imageUnavailable:
                return L10n.detail.lockScreenImageUnavailable
            case .exportUnavailable:
                return L10n.detail.lockScreenConversionUnavailable
            case .conversionFailed(let message):
                return message.isEmpty ? L10n.detail.lockScreenConversionFailed : message
            case .screenSaverConfigurationFailed:
                return L10n.detail.lockScreenScreenSaverFailed
            case .reloadFailed:
                return L10n.detail.lockScreenReloadFailed
            case .restoreUnavailable:
                return L10n.settings.lockScreenRestoreUnavailable
            }
        }
    }

    private final class VideoTranscodeBox: @unchecked Sendable {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let writer: AVAssetWriter
        let input: AVAssetWriterInput

        init(
            reader: AVAssetReader,
            output: AVAssetReaderTrackOutput,
            writer: AVAssetWriter,
            input: AVAssetWriterInput
        ) {
            self.reader = reader
            self.output = output
            self.writer = writer
            self.input = input
        }
    }

    private final class StillWriterBox: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let pixelBuffer: CVPixelBuffer

        init(
            writer: AVAssetWriter,
            input: AVAssetWriterInput,
            adaptor: AVAssetWriterInputPixelBufferAdaptor,
            pixelBuffer: CVPixelBuffer
        ) {
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            self.pixelBuffer = pixelBuffer
        }
    }

    private struct Paths {
        let videos: URL
        let manifest: URL
        let storeIndex: URL
        let workingRoot: URL
        let backups: URL
        let currentMovie: URL
        let indexRepairBackup: URL
        let indexActivationBackup: URL
    }

    private struct AerialProcessSnapshot {
        var processIDs: Set<Int> = []
        var assetIDs: Set<String> = []
    }

    private enum DefaultsKey {
        static let managedAssetIDs = "wallpaper.lockScreen.managedAssetIDs"
        static let legacyAssetIDPrefix = "wallpaper.lockScreenAerialID."
        static let screenSaverBackupCaptured = "wallpaper.lockScreen.screenSaverBackupCaptured"
        static let previousScreenSaverModule = "wallpaper.lockScreen.previousScreenSaverModule"
    }

    private enum ScreenSaverPreference {
        static let applicationID = "com.apple.screensaver"
        static let moduleKey = "moduleDict"
        static let aerialsExtensionPath = "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex"
    }

    private let logger = Logger(subsystem: "com.wallpaperexchange.mac", category: "aerial-lock-screen")
    private let fm = FileManager.default
    private var rendererResetTask: Task<Void, Never>?
    private var screenWasLocked = false

    private init() {
        installWakeObservers()
    }

    var canRestoreOriginals: Bool {
        guard Self.isSupported else { return false }
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenSaverBackupCaptured) { return true }
        guard let paths = try? paths() else { return false }
        return !backupURLs(in: paths.backups).isEmpty
            || fm.fileExists(atPath: paths.indexActivationBackup.path)
    }

    /// Converts the selected wallpaper into an Aerial-compatible movie, backs
    /// up every active lock-screen Aerial and atomically swaps the cached files.
    func apply(wallpaper: Wallpaper, sourceURL: URL, sourceIsVideo: Bool) async throws {
        guard Self.isSupported else { throw AerialError.unsupported }

        let paths = try paths()
        try ensureWorkingDirectories(paths)
        let previousSnapshot = runningAerialSnapshot(paths: paths)
        let assetIDs = try activeLockScreenAerialAssetIDs(paths: paths, processSnapshot: previousSnapshot)
        guard !assetIDs.isEmpty else { throw AerialError.noAerialSelected }

        let destinations = try assetIDs.map { assetID -> URL in
            let destination = paths.videos.appendingPathComponent("\(assetID).mov")
            guard fm.fileExists(atPath: destination.path) else {
                throw AerialError.aerialVideoMissing
            }
            guard fm.isWritableFile(atPath: destination.path), fm.isWritableFile(atPath: paths.videos.path) else {
                throw AerialError.permissionRequired
            }
            return destination
        }

        let prepared = paths.workingRoot.appendingPathComponent("prepared-\(UUID().uuidString).mov")
        defer { try? fm.removeItem(at: prepared) }
        if sourceIsVideo {
            try await exportVideo(source: sourceURL, destination: prepared)
        } else {
            try await makeStillMovie(source: sourceURL, destination: prepared)
        }

        try configureScreenSaverForAerials()
        try replaceFileAtomically(source: prepared, destination: paths.currentMovie)
        var replacedAssets: [(assetID: String, destination: URL)] = []
        do {
            for (assetID, destination) in zip(assetIDs, destinations) {
                try backupOriginalIfNeeded(assetID: assetID, source: destination, paths: paths)
                try replaceFileAtomically(source: paths.currentMovie, destination: destination)
                replacedAssets.append((assetID, destination))
            }
        } catch {
            for replaced in replacedAssets.reversed() {
                let backup = paths.backups.appendingPathComponent("\(replaced.assetID).mov")
                try? replaceFileAtomically(source: backup, destination: replaced.destination)
            }
            throw error
        }

        // A separate image Desktop choice plus an Aerial Idle choice previews
        // correctly in System Settings, but loginwindow asks WallpaperAgent for
        // the Desktop choice and keeps the video timeline at rate 0. Apple's
        // animated lock screens use one global linked Aerial choice instead.
        // Only videos need that linkage; still lock screens already work via
        // the selected Idle asset without taking over the system desktop.
        if sourceIsVideo, let assetID = assetIDs.first {
            try activateAnimatedAerialSelection(assetID: assetID, paths: paths)
        }

        UserDefaults.standard.set(assetIDs, forKey: DefaultsKey.managedAssetIDs)
        restartWallpaperProcesses()
        try await waitForAerialReload(
            assetIDs: Set(assetIDs),
            previousProcessIDs: previousSnapshot.processIDs,
            paths: paths
        )
        logger.notice("applied lock-screen wallpaper id=\(wallpaper.id, privacy: .public) to \(assetIDs.count, privacy: .public) Aerial asset(s)")
    }

    /// Restores every Aerial file ever replaced by Wallpaper Exchange. Backups
    /// are only deleted after all originals have been put back successfully.
    func restoreOriginals() throws {
        guard Self.isSupported else { throw AerialError.unsupported }
        let paths = try paths()
        let backups = backupURLs(in: paths.backups)
        let hasScreenSaverBackup = UserDefaults.standard.bool(forKey: DefaultsKey.screenSaverBackupCaptured)
        let hasIndexBackup = fm.fileExists(atPath: paths.indexActivationBackup.path)
        guard !backups.isEmpty || hasScreenSaverBackup || hasIndexBackup else {
            throw AerialError.restoreUnavailable
        }

        for backup in backups {
            let assetID = backup.deletingPathExtension().lastPathComponent
            let destination = paths.videos.appendingPathComponent("\(assetID).mov")
            guard fm.isWritableFile(atPath: paths.videos.path) else {
                throw AerialError.permissionRequired
            }
            try replaceFileAtomically(source: backup, destination: destination)
        }

        try restoreWallpaperStoreIfNeeded(paths: paths)
        try restoreScreenSaverModuleIfNeeded()

        for backup in backups {
            try? fm.removeItem(at: backup)
        }
        try? fm.removeItem(at: paths.indexActivationBackup)
        try? fm.removeItem(at: paths.currentMovie)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.managedAssetIDs)
        restartWallpaperProcesses()
        logger.notice("restored \(backups.count, privacy: .public) original Aerial asset(s)")
    }

    /// The lock screen initially displays a still wallpaper. Motion starts in
    /// the screen-saver phase, which must be backed by Apple's Aerial extension.
    /// Preserve the user's previous module once so Settings can restore it.
    private func configureScreenSaverForAerials() throws {
        let defaults = UserDefaults.standard
        let current = currentScreenSaverModule()
        let capturedNow = !defaults.bool(forKey: DefaultsKey.screenSaverBackupCaptured)
        if capturedNow {
            if let current {
                defaults.set(current, forKey: DefaultsKey.previousScreenSaverModule)
            } else {
                defaults.removeObject(forKey: DefaultsKey.previousScreenSaverModule)
            }
            defaults.set(true, forKey: DefaultsKey.screenSaverBackupCaptured)
        }

        if current?["path"] as? String == ScreenSaverPreference.aerialsExtensionPath { return }

        let aerialsModule: [String: Any] = [
            "moduleName": "WallpaperAerialsExtension",
            "path": ScreenSaverPreference.aerialsExtensionPath,
            "type": 0,
        ]
        setCurrentScreenSaverModule(aerialsModule)
        guard synchronizeScreenSaverPreferences(),
              currentScreenSaverModule()?["path"] as? String == ScreenSaverPreference.aerialsExtensionPath else {
            setCurrentScreenSaverModule(current)
            _ = synchronizeScreenSaverPreferences()
            if capturedNow {
                defaults.removeObject(forKey: DefaultsKey.previousScreenSaverModule)
                defaults.removeObject(forKey: DefaultsKey.screenSaverBackupCaptured)
            }
            throw AerialError.screenSaverConfigurationFailed
        }
        logger.notice("configured the lock-screen screen saver to use WallpaperAerialsExtension")
    }

    private func restoreScreenSaverModuleIfNeeded() throws {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.screenSaverBackupCaptured) else { return }

        let previous = defaults.dictionary(forKey: DefaultsKey.previousScreenSaverModule)
        setCurrentScreenSaverModule(previous)
        guard synchronizeScreenSaverPreferences(), screenSaverModulesMatch(currentScreenSaverModule(), previous) else {
            throw AerialError.screenSaverConfigurationFailed
        }
        defaults.removeObject(forKey: DefaultsKey.previousScreenSaverModule)
        defaults.removeObject(forKey: DefaultsKey.screenSaverBackupCaptured)
        logger.notice("restored the previous lock-screen screen saver module")
    }

    private func currentScreenSaverModule() -> [String: Any]? {
        CFPreferencesCopyValue(
            ScreenSaverPreference.moduleKey as CFString,
            ScreenSaverPreference.applicationID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String: Any]
    }

    private func setCurrentScreenSaverModule(_ module: [String: Any]?) {
        CFPreferencesSetValue(
            ScreenSaverPreference.moduleKey as CFString,
            module as CFDictionary?,
            ScreenSaverPreference.applicationID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private func synchronizeScreenSaverPreferences() -> Bool {
        CFPreferencesSynchronize(
            ScreenSaverPreference.applicationID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private func screenSaverModulesMatch(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return NSDictionary(dictionary: lhs).isEqual(to: rhs)
        default:
            return false
        }
    }

    private func paths() throws -> Paths {
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AerialError.storeUnavailable
        }
        let systemRoot = appSupport.appendingPathComponent("com.apple.wallpaper", isDirectory: true)
        let workingRoot = appSupport.appendingPathComponent("WallpaperExchange/LockScreen", isDirectory: true)
        return Paths(
            videos: systemRoot.appendingPathComponent("aerials/videos", isDirectory: true),
            manifest: systemRoot.appendingPathComponent("aerials/manifest/entries.json"),
            storeIndex: systemRoot.appendingPathComponent("Store/Index.plist"),
            workingRoot: workingRoot,
            backups: workingRoot.appendingPathComponent("Backups", isDirectory: true),
            currentMovie: workingRoot.appendingPathComponent("Current.mov"),
            indexRepairBackup: workingRoot.appendingPathComponent("Index-before-legacy-repair.plist"),
            indexActivationBackup: workingRoot.appendingPathComponent("Index-before-animated-lock.plist")
        )
    }

    private func ensureWorkingDirectories(_ paths: Paths) throws {
        guard fm.fileExists(atPath: paths.storeIndex.path),
              fm.fileExists(atPath: paths.manifest.path),
              fm.fileExists(atPath: paths.videos.path) else {
            throw AerialError.storeUnavailable
        }
        try fm.createDirectory(at: paths.backups, withIntermediateDirectories: true)
    }

    private func backupURLs(in directory: URL) -> [URL] {
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "mov" }
    }

    private func backupOriginalIfNeeded(assetID: String, source: URL, paths: Paths) throws {
        let backup = paths.backups.appendingPathComponent("\(assetID).mov")
        guard !fm.fileExists(atPath: backup.path) else { return }
        try fm.copyItem(at: source, to: backup)
    }

    private func replaceFileAtomically(source: URL, destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".wallpaperexchange-\(UUID().uuidString).mov")
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)

        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    private func activeLockScreenAerialAssetIDs(
        paths: Paths,
        processSnapshot: AerialProcessSnapshot
    ) throws -> [String] {
        let manifestIDs = try manifestAssetIDs(from: paths.manifest)
        guard !manifestIDs.isEmpty else { throw AerialError.storeUnavailable }

        let indexIDs = try aerialAssetIDs(from: paths.storeIndex, sectionName: "Idle")
        let validIndexIDs = Set(indexIDs.filter {
            manifestIDs.contains($0) && fm.fileExists(atPath: paths.videos.appendingPathComponent("\($0).mov").path)
        })
        let runningIDs = Set(processSnapshot.assetIDs.filter {
            manifestIDs.contains($0) && fm.fileExists(atPath: paths.videos.appendingPathComponent("\($0).mov").path)
        })

        // A valid Idle choice remains the safest source because the Aerial
        // extension can also have a desktop preview open. If the running
        // extension confirms one of those IDs, prefer the confirmed subset.
        if !validIndexIDs.isEmpty {
            let confirmed = validIndexIDs.intersection(runningIDs)
            return (confirmed.isEmpty ? validIndexIDs : confirmed).sorted()
        }

        // Builds before 2.1.3 generated synthetic asset IDs and rewrote every
        // Idle node. Those IDs survive in Index.plist after Apple refreshes its
        // manifest, so replacing their files reports success while the system
        // continues rendering a different, real Aerial. Only repair this known
        // legacy state when the extension exposes one unambiguous real asset.
        if isLegacySyntheticSelection(indexIDs), runningIDs.count == 1, let actualID = runningIDs.first {
            try repairLegacyAerialSelection(assetID: actualID, paths: paths)
            return [actualID]
        }

        // Some clean macOS installations expose the selected Aerial only via a
        // Linked node. It is still required to be a real Apple manifest entry.
        let linkedIDs = Set(try aerialAssetIDs(from: paths.storeIndex, sectionName: "Linked").filter {
            manifestIDs.contains($0) && fm.fileExists(atPath: paths.videos.appendingPathComponent("\($0).mov").path)
        })
        if !linkedIDs.isEmpty { return linkedIDs.sorted() }
        throw AerialError.noAerialSelected
    }

    private func manifestAssetIDs(from manifestURL: URL) throws -> Set<String> {
        let data = try Data(contentsOf: manifestURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]] else {
            throw AerialError.storeUnavailable
        }
        return Set(assets.compactMap { asset in
            guard let id = asset["id"] as? String, isSafeAssetID(id) else { return nil }
            return id
        })
    }

    private func aerialAssetIDs(from indexURL: URL, sectionName: String) throws -> Set<String> {
        guard fm.fileExists(atPath: indexURL.path) else { throw AerialError.storeUnavailable }
        let data = try Data(contentsOf: indexURL)
        let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        var ids = Set<String>()
        collectAerialAssetIDs(in: root, sectionName: sectionName, output: &ids)
        return ids
    }

    private func collectAerialAssetIDs(in node: Any, sectionName: String, output: inout Set<String>) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if key.caseInsensitiveCompare(sectionName) == .orderedSame {
                    collectAerialChoices(in: value, output: &output)
                }
                collectAerialAssetIDs(in: value, sectionName: sectionName, output: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectAerialAssetIDs(in: value, sectionName: sectionName, output: &output)
            }
        }
    }

    private func collectAerialChoices(in node: Any, output: inout Set<String>) {
        if let dictionary = node as? [String: Any] {
            if let provider = dictionary["Provider"] as? String,
               provider == "com.apple.wallpaper.choice.aerials",
               let configuration = dictionary["Configuration"] as? Data,
               let assetID = assetID(from: configuration),
               isSafeAssetID(assetID) {
                output.insert(assetID)
            }
            for value in dictionary.values {
                collectAerialChoices(in: value, output: &output)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectAerialChoices(in: value, output: &output)
            }
        }
    }

    private func assetID(from configuration: Data) -> String? {
        guard let root = try? PropertyListSerialization.propertyList(from: configuration, options: [], format: nil) else {
            return nil
        }
        return findStringValue(named: "assetID", in: root)
    }

    private func isSafeAssetID(_ assetID: String) -> Bool {
        !assetID.isEmpty && assetID.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }
    }

    private func findStringValue(named name: String, in node: Any) -> String? {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary where key.caseInsensitiveCompare(name) == .orderedSame {
                if let string = value as? String, !string.isEmpty { return string }
            }
            for value in dictionary.values {
                if let found = findStringValue(named: name, in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findStringValue(named: name, in: value) { return found }
            }
        }
        return nil
    }

    private func isLegacySyntheticSelection(_ assetIDs: Set<String>) -> Bool {
        guard !assetIDs.isEmpty else { return false }
        let legacyIDs = Set(UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> String? in
            guard key.hasPrefix(DefaultsKey.legacyAssetIDPrefix), let value = value as? String else { return nil }
            return value
        })
        return !legacyIDs.isEmpty && assetIDs.isSubset(of: legacyIDs)
    }

    private func repairLegacyAerialSelection(assetID: String, paths: Paths) throws {
        let originalData = try Data(contentsOf: paths.storeIndex)
        guard var root = try PropertyListSerialization.propertyList(
            from: originalData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw AerialError.storeUnavailable
        }

        let repairedIdleNodes = replaceAerialAssetIDs(in: &root, sectionName: "Idle", assetID: assetID)
        let repairedLinkedNodes = replaceAerialAssetIDs(in: &root, sectionName: "Linked", assetID: assetID)
        guard repairedIdleNodes + repairedLinkedNodes > 0 else { throw AerialError.noAerialSelected }

        if !fm.fileExists(atPath: paths.indexRepairBackup.path) {
            try originalData.write(to: paths.indexRepairBackup, options: .atomic)
        }
        let repairedData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        do {
            try repairedData.write(to: paths.storeIndex, options: .atomic)
        } catch {
            try? originalData.write(to: paths.storeIndex, options: .atomic)
            throw error
        }

        updateSystemWallpaperPointer(assetID: assetID, paths: paths)
        clearLegacyAssetIDDefaults()
        logger.notice("repaired legacy synthetic Aerial selection with real asset \(assetID, privacy: .public)")
    }

    private func activateAnimatedAerialSelection(assetID: String, paths: Paths) throws {
        let originalData = try Data(contentsOf: paths.storeIndex)
        guard var root = try PropertyListSerialization.propertyList(
            from: originalData,
            options: [.mutableContainersAndLeaves],
            format: nil
        ) as? [String: Any] else {
            throw AerialError.storeUnavailable
        }

        if !fm.fileExists(atPath: paths.indexActivationBackup.path) {
            try originalData.write(to: paths.indexActivationBackup, options: .atomic)
        }

        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
        let choice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.aerials",
            "Files": [] as [Any],
            "Configuration": configuration,
        ]
        let linked: [String: Any] = [
            "Content": ["Choices": [choice]],
            "LastSet": Date(),
            "LastUse": Date(),
        ]
        let entry: [String: Any] = [
            "Type": "linked",
            "Linked": linked,
        ]

        // loginwindow resolves these global nodes rather than a display's Idle
        // node. Keep every display/space entry untouched: those entries own the
        // desktop wallpaper, while the global linked choice drives lock-screen
        // playback. Replacing them would also change the desktop when the user
        // selected the lock-screen-only target.
        root["SystemDefault"] = entry
        root["AllSpacesAndDisplays"] = entry

        let linkedData = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        do {
            try linkedData.write(to: paths.storeIndex, options: .atomic)
        } catch {
            try? originalData.write(to: paths.storeIndex, options: .atomic)
            throw error
        }
        updateSystemWallpaperPointer(assetID: assetID, paths: paths)
        logger.notice("activated lock-screen linked Aerial selection \(assetID, privacy: .public) while preserving desktop entries")
    }

    private func restoreWallpaperStoreIfNeeded(paths: Paths) throws {
        guard fm.fileExists(atPath: paths.indexActivationBackup.path) else { return }
        let backup = try Data(contentsOf: paths.indexActivationBackup)
        let current = try Data(contentsOf: paths.storeIndex)
        do {
            try backup.write(to: paths.storeIndex, options: .atomic)
        } catch {
            try? current.write(to: paths.storeIndex, options: .atomic)
            throw error
        }
        logger.notice("restored wallpaper store from before animated lock-screen activation")
    }

    private func replaceAerialAssetIDs(
        in dictionary: inout [String: Any],
        sectionName: String,
        assetID: String
    ) -> Int {
        var replacements = 0
        for key in Array(dictionary.keys) {
            if key.caseInsensitiveCompare(sectionName) == .orderedSame,
               var section = dictionary[key] as? [String: Any] {
                replacements += replaceAerialChoices(in: &section, assetID: assetID)
                dictionary[key] = section
            }

            if var child = dictionary[key] as? [String: Any] {
                replacements += replaceAerialAssetIDs(in: &child, sectionName: sectionName, assetID: assetID)
                dictionary[key] = child
            } else if var children = dictionary[key] as? [[String: Any]] {
                for index in children.indices {
                    replacements += replaceAerialAssetIDs(
                        in: &children[index],
                        sectionName: sectionName,
                        assetID: assetID
                    )
                }
                dictionary[key] = children
            }
        }
        return replacements
    }

    private func replaceAerialChoices(in dictionary: inout [String: Any], assetID: String) -> Int {
        var replacements = 0
        if dictionary["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
           let configuration = dictionary["Configuration"] as? Data,
           var decoded = try? PropertyListSerialization.propertyList(
            from: configuration,
            options: [],
            format: nil
           ) as? [String: Any] {
            decoded["assetID"] = assetID
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: decoded,
                format: .binary,
                options: 0
            ) {
                dictionary["Configuration"] = data
                replacements += 1
            }
        }

        for key in Array(dictionary.keys) {
            if var child = dictionary[key] as? [String: Any] {
                replacements += replaceAerialChoices(in: &child, assetID: assetID)
                dictionary[key] = child
            } else if var children = dictionary[key] as? [[String: Any]] {
                for index in children.indices {
                    replacements += replaceAerialChoices(in: &children[index], assetID: assetID)
                }
                dictionary[key] = children
            }
        }
        return replacements
    }

    private func updateSystemWallpaperPointer(assetID: String, paths: Paths) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = [
            "write",
            "com.apple.wallpaper",
            "SystemWallpaperURL",
            paths.videos.appendingPathComponent("\(assetID).mov").absoluteString,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("failed to repair SystemWallpaperURL: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearLegacyAssetIDDefaults() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix(DefaultsKey.legacyAssetIDPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func runningAerialSnapshot(paths: Paths) -> AerialProcessSnapshot {
        let executable = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard fm.isExecutableFile(atPath: executable.path) else { return AerialProcessSnapshot() }

        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["-n", "-Fpn", "-c", "WallpaperAerialsExtension"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("failed to inspect running Aerial extension: \(error.localizedDescription, privacy: .public)")
            return AerialProcessSnapshot()
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return AerialProcessSnapshot() }
        var snapshot = AerialProcessSnapshot()
        let videosPath = paths.videos.standardizedFileURL.path
        for line in text.split(separator: "\n") {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            if prefix == "p", let pid = Int(value) {
                snapshot.processIDs.insert(pid)
            } else if prefix == "n" {
                let normalizedPath = value.replacingOccurrences(of: " (deleted)", with: "")
                let url = URL(fileURLWithPath: normalizedPath).standardizedFileURL
                guard url.deletingLastPathComponent().path == videosPath,
                      url.pathExtension.lowercased() == "mov" else { continue }
                let assetID = url.deletingPathExtension().lastPathComponent
                if isSafeAssetID(assetID) { snapshot.assetIDs.insert(assetID) }
            }
        }
        return snapshot
    }

    private func waitForAerialReload(
        assetIDs: Set<String>,
        previousProcessIDs: Set<Int>,
        paths: Paths
    ) async throws {
        for _ in 0..<32 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let snapshot = runningAerialSnapshot(paths: paths)
            let loadedTarget = !snapshot.assetIDs.intersection(assetIDs).isEmpty
            let relaunched = previousProcessIDs.isEmpty || !snapshot.processIDs.isSubset(of: previousProcessIDs)
            if loadedTarget && relaunched { return }
        }
        throw AerialError.reloadFailed
    }

    private func exportVideo(source: URL, destination: URL) async throws {
        try? fm.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AerialError.exportUnavailable
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let width = max(2, Int(abs(naturalSize.width)).roundedDownToEven)
        let height = max(2, Int(abs(naturalSize.height)).roundedDownToEven)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        } catch {
            throw AerialError.conversionFailed(error.localizedDescription)
        }

        // WallpaperAerialsExtension opens H.264 movies but only renders their
        // still frame on the Tahoe lock screen. Apple's assets use hvc1 Main 10,
        // so decode into a 10-bit pixel buffer and let VideoToolbox produce the
        // same hardware-native profile without requiring an external ffmpeg.
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AerialError.exportUnavailable }
        reader.add(output)

        let bitRate = min(30_000_000, max(12_000_000, width * height * 5))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoAllowFrameReorderingKey: true,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = preferredTransform
        guard writer.canAdd(input) else { throw AerialError.exportUnavailable }
        writer.add(input)

        let box = VideoTranscodeBox(reader: reader, output: output, writer: writer, input: input)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard box.writer.startWriting(), box.reader.startReading() else {
                    let message = box.writer.error?.localizedDescription
                        ?? box.reader.error?.localizedDescription
                        ?? L10n.detail.lockScreenConversionFailed
                    continuation.resume(throwing: AerialError.conversionFailed(message))
                    return
                }
                box.writer.startSession(atSourceTime: .zero)

                while box.reader.status == .reading {
                    if box.input.isReadyForMoreMediaData {
                        guard let sample = box.output.copyNextSampleBuffer() else { break }
                        guard box.input.append(sample) else {
                            box.reader.cancelReading()
                            box.writer.cancelWriting()
                            let message = box.writer.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed
                            continuation.resume(throwing: AerialError.conversionFailed(message))
                            return
                        }
                    } else {
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                }

                guard box.reader.status == .completed else {
                    box.writer.cancelWriting()
                    let message = box.reader.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed
                    continuation.resume(throwing: AerialError.conversionFailed(message))
                    return
                }
                box.input.markAsFinished()
                box.writer.finishWriting {
                    if box.writer.status == .completed {
                        continuation.resume()
                    } else {
                        let message = box.writer.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed
                        continuation.resume(throwing: AerialError.conversionFailed(message))
                    }
                }
            }
        }
    }

    private func makeStillMovie(source: URL, destination: URL) async throws {
        guard let image = NSImage(contentsOf: source),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AerialError.imageUnavailable
        }

        let maximumDimension = 3840.0
        let sourceWidth = Double(cgImage.width)
        let sourceHeight = Double(cgImage.height)
        let scale = min(1, maximumDimension / max(sourceWidth, sourceHeight))
        let width = max(2, Int(sourceWidth * scale) / 2 * 2)
        let height = max(2, Int(sourceHeight * scale) / 2 * 2)
        try? fm.removeItem(at: destination)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        } catch {
            throw AerialError.conversionFailed(error.localizedDescription)
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(24_000_000, max(4_000_000, width * height * 3)),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(input) else { throw AerialError.exportUnavailable }
        writer.add(input)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { throw AerialError.imageUnavailable }
        try draw(cgImage, into: pixelBuffer, width: width, height: height)

        guard writer.startWriting() else {
            throw AerialError.conversionFailed(writer.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed)
        }
        writer.startSession(atSourceTime: .zero)
        let writerBox = StillWriterBox(writer: writer, input: input, adaptor: adaptor, pixelBuffer: pixelBuffer)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let frameRate: Int32 = 30
                let frameCount = 8 * Int(frameRate)
                let readinessDeadline = Date().addingTimeInterval(60)
                for frame in 0..<frameCount {
                    while !writerBox.input.isReadyForMoreMediaData {
                        if writerBox.writer.status == .failed || writerBox.writer.status == .cancelled {
                            continuation.resume(throwing: AerialError.conversionFailed(writerBox.writer.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed))
                            return
                        }
                        if Date() >= readinessDeadline {
                            writerBox.writer.cancelWriting()
                            continuation.resume(throwing: AerialError.conversionFailed(L10n.detail.lockScreenConversionFailed))
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                    let time = CMTime(value: CMTimeValue(frame), timescale: frameRate)
                    guard writerBox.adaptor.append(writerBox.pixelBuffer, withPresentationTime: time) else {
                        continuation.resume(throwing: AerialError.conversionFailed(writerBox.writer.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed))
                        return
                    }
                }
                writerBox.input.markAsFinished()
                writerBox.writer.finishWriting {
                    if writerBox.writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AerialError.conversionFailed(writerBox.writer.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed))
                    }
                }
            }
        }
    }

    private func draw(_ image: CGImage, into pixelBuffer: CVPixelBuffer, width: Int, height: Int) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            throw AerialError.imageUnavailable
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func installWakeObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleManagedMovieReset(trigger: "session active") }
        }
        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markScreenLocked() }
        }
        distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleManagedMovieReset(trigger: "screen unlocked") }
        }
    }

    private func markScreenLocked() {
        screenWasLocked = true
        rendererResetTask?.cancel()
        rendererResetTask = nil
    }

    /// Unlock commonly emits several notifications seconds apart. Accept only
    /// the first notification paired with a preceding lock, then delay until
    /// loginwindow has released the renderer before resetting its timeline.
    private func scheduleManagedMovieReset(trigger: String) {
        guard screenWasLocked else { return }
        screenWasLocked = false
        rendererResetTask?.cancel()
        rendererResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled, let self else { return }
            self.reapplyManagedMovieAfterWake(trigger: trigger)
            self.rendererResetTask = nil
        }
    }

    private func reapplyManagedMovieAfterWake(trigger: String) {
        guard Self.isSupported,
              let assetIDs = UserDefaults.standard.stringArray(forKey: DefaultsKey.managedAssetIDs),
              !assetIDs.isEmpty,
              let paths = try? paths(),
              fm.fileExists(atPath: paths.currentMovie.path) else { return }

        var replaced = 0
        for assetID in assetIDs {
            let destination = paths.videos.appendingPathComponent("\(assetID).mov")
            guard fm.fileExists(atPath: destination.path) else { continue }
            do {
                try replaceFileAtomically(source: paths.currentMovie, destination: destination)
                replaced += 1
            } catch {
                logger.error("failed to reapply managed Aerial \(assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if replaced > 0 {
            restartWallpaperProcesses()
            logger.notice("reset managed Aerial after \(trigger, privacy: .public)")
        }
    }

    private func restartWallpaperProcesses() {
        // Stop the renderer first, then its owners. Killing WallpaperAgent
        // before the extension lets launchd create a new renderer that the next
        // kill immediately tears down again, which made the first apply flaky.
        for processName in [
            "WallpaperAerialsExtension",
            "WallpaperImageExtension",
            "WallpaperLegacyExtension",
            "legacyScreenSaver",
            "WallpaperAgent",
            "idleassetsd",
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [processName]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}

private extension Int {
    var roundedDownToEven: Int { self / 2 * 2 }
}
