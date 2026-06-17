import AppKit
import AVFoundation
import Foundation
import os.log

/// Experimental macOS 26+ lock-screen live wallpaper support.
///
/// Apple does not expose a stable AppKit lock-screen wallpaper API. Wallspace
/// appears to use the system Aerial wallpaper cache instead, so this service
/// keeps that private-path work isolated from the normal desktop wallpaper
/// path. If Apple changes the Aerial manifest/cache layout, this is the only
/// file that should need surgery.
final class AerialLockScreenService {
    static let shared = AerialLockScreenService()

    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }

    static var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    private enum Constants {
        static let categoryID = "B56F8C97-D8EA-4D31-A07A-8F72727B72F5"
        static let subcategoryID = "615C97DA-A6F6-4571-9EA1-6494972E846E"
        static let assetIDDefaultsPrefix = "wallpaper.lockScreenAerialID."
    }

    enum AerialError: LocalizedError {
        case unsupported
        case exportUnavailable
        case conversionFailed(String)
        case thumbnailFailed
        case manifestUnavailable
        case extensionUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return L10n.detail.lockScreenUnavailable
            case .exportUnavailable:
                return L10n.detail.lockScreenConversionUnavailable
            case .conversionFailed(let message):
                return message.isEmpty ? L10n.detail.lockScreenConversionFailed : message
            case .thumbnailFailed:
                return L10n.detail.lockScreenThumbnailFailed
            case .manifestUnavailable:
                return L10n.detail.lockScreenManifestFailed
            case .extensionUnavailable:
                return L10n.detail.lockScreenExtensionFailed
            }
        }
    }

    private let logger = Logger(subsystem: "com.wallpaperexchange.mac", category: "aerial-lock-screen")
    private let fm = FileManager.default

    private init() {}

    func applyStaticImage(imageURL: URL) throws {
        logger.notice("applying static lock-screen image \(imageURL.path, privacy: .public)")
        let paths = try aerialPaths()
        try ensureDirectories(paths)

        do {
            try updateWallpaperStoreIndexForImage(indexURL: paths.storeIndex, backupURL: paths.storeBackup, imageURL: imageURL)
        } catch {
            logger.error("failed to update lock-screen image store: \(error.localizedDescription, privacy: .public)")
        }
        try applyStaticLockScreenFallback(imageURL: imageURL)
    }

    func apply(wallpaper: Wallpaper, videoURL: URL, thumbnailURL: URL?) async throws {
        guard Self.isSupported else { throw AerialError.unsupported }

        let assetID = assetID(for: wallpaper.id)
        logger.notice("applying aerial lock-screen wallpaper id=\(wallpaper.id, privacy: .public) asset=\(assetID, privacy: .public)")
        let paths = try aerialPaths()
        try ensureDirectories(paths)

        let videoDestination = paths.videos.appendingPathComponent("\(assetID).mov")
        let thumbnailDestination = paths.thumbnails.appendingPathComponent("\(assetID).png")

        try await convertVideoIfNeeded(source: videoURL, destination: videoDestination)
        try await writeThumbnail(source: thumbnailURL, videoURL: videoURL, destination: thumbnailDestination)
        try updateManifest(
            manifestURL: paths.manifest,
            backupURL: paths.backup,
            wallpaper: wallpaper,
            assetID: assetID,
            videoURL: videoDestination,
            thumbnailURL: thumbnailDestination
        )
        try updateWallpaperStoreIndex(
            indexURL: paths.storeIndex,
            backupURL: paths.storeBackup,
            assetID: assetID,
            thumbnailURL: thumbnailDestination
        )
        try applySystemWallpaperPointers(videoURL: videoDestination, thumbnailURL: thumbnailDestination)

        do {
            try restartAerialExtension()
        } catch {
            logger.error("lock-screen static fallback was applied, but Aerial restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct AerialPaths {
        let root: URL
        let manifestDir: URL
        let manifest: URL
        let backup: URL
        let videos: URL
        let thumbnails: URL
        let storeIndex: URL
        let storeBackup: URL
    }

    private func aerialPaths() throws -> AerialPaths {
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AerialError.manifestUnavailable
        }
        let root = appSupport.appendingPathComponent("com.apple.wallpaper/aerials", isDirectory: true)
        let manifestDir = root.appendingPathComponent("manifest", isDirectory: true)
        let manifest = manifestDir.appendingPathComponent("entries.json")
        return AerialPaths(
            root: root,
            manifestDir: manifestDir,
            manifest: manifest,
            backup: manifestDir.appendingPathComponent("entries.json.wallpaperexchange.backup"),
            videos: root.appendingPathComponent("videos", isDirectory: true),
            thumbnails: root.appendingPathComponent("thumbnails", isDirectory: true),
            storeIndex: appSupport.appendingPathComponent("com.apple.wallpaper/Store/Index.plist"),
            storeBackup: appSupport.appendingPathComponent("com.apple.wallpaper/Store/Index.plist.wallpaperexchange.backup")
        )
    }

    private func ensureDirectories(_ paths: AerialPaths) throws {
        try fm.createDirectory(at: paths.manifestDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.videos, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.thumbnails, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.storeIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func assetID(for wallpaperID: Int) -> String {
        let key = "\(Constants.assetIDDefaultsPrefix)\(wallpaperID)"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString.uppercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    private func convertVideoIfNeeded(source: URL, destination: URL) async throws {
        if fm.fileExists(atPath: destination.path) { return }
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(destination.deletingPathExtension().lastPathComponent).tmp.mov")
        try? fm.removeItem(at: temporary)

        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AerialError.exportUnavailable
        }
        exporter.outputURL = temporary
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true

        let exportSession = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.session.exportAsynchronously {
                switch exportSession.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let message = exportSession.session.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed
                    continuation.resume(throwing: AerialError.conversionFailed(message))
                default:
                    continuation.resume(throwing: AerialError.conversionFailed(L10n.detail.lockScreenConversionFailed))
                }
            }
        }

        try? fm.removeItem(at: destination)
        try fm.moveItem(at: temporary, to: destination)
    }

    private func writeThumbnail(source: URL?, videoURL: URL, destination: URL) async throws {
        if fm.fileExists(atPath: destination.path) { return }
        if let source, let image = NSImage(contentsOf: source), try writePNG(image: image, to: destination) {
            return
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cgImage: CGImage
        do {
            cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        } catch {
            throw AerialError.thumbnailFailed
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard try writePNG(image: image, to: destination) else {
            throw AerialError.thumbnailFailed
        }
    }

    private func writePNG(image: NSImage, to destination: URL) throws -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        try data.write(to: destination, options: .atomic)
        return true
    }

    private func updateManifest(
        manifestURL: URL,
        backupURL: URL,
        wallpaper: Wallpaper,
        assetID: String,
        videoURL: URL,
        thumbnailURL: URL
    ) throws {
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw AerialError.manifestUnavailable
        }
        let originalData = try Data(contentsOf: manifestURL)
        if !fm.fileExists(atPath: backupURL.path) {
            try originalData.write(to: backupURL, options: .atomic)
        }

        guard var root = try JSONSerialization.jsonObject(with: originalData) as? [String: Any] else {
            throw AerialError.manifestUnavailable
        }

        var assets = root["assets"] as? [[String: Any]] ?? []
        assets.removeAll { item in
            item["id"] as? String == assetID || item["shotID"] as? String == shotID(for: wallpaper.id)
        }
        assets.append(assetEntry(
            wallpaper: wallpaper,
            assetID: assetID,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL
        ))
        root["assets"] = assets

        var categories = root["categories"] as? [[String: Any]] ?? []
        if let index = categories.firstIndex(where: { $0["id"] as? String == Constants.categoryID }) {
            categories[index] = categoryEntry(representativeAssetID: assetID, thumbnailURL: thumbnailURL)
        } else {
            categories.append(categoryEntry(representativeAssetID: assetID, thumbnailURL: thumbnailURL))
        }
        root["categories"] = categories

        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            try? originalData.write(to: manifestURL, options: .atomic)
            throw AerialError.manifestUnavailable
        }
    }

    private func assetEntry(wallpaper: Wallpaper, assetID: String, videoURL: URL, thumbnailURL: URL) -> [String: Any] {
        [
            "accessibilityLabel": wallpaper.title,
            "categories": [Constants.categoryID],
            "id": assetID,
            "includeInShuffle": true,
            "localizedNameKey": wallpaper.title,
            "pointsOfInterest": [:],
            "preferredOrder": -1000,
            "previewImage": thumbnailURL.absoluteString,
            "shotID": shotID(for: wallpaper.id),
            "showInTopLevel": true,
            "subcategories": [Constants.subcategoryID],
            "url-4K-SDR-240FPS": videoURL.absoluteString,
        ]
    }

    private func categoryEntry(representativeAssetID: String, thumbnailURL: URL) -> [String: Any] {
        [
            "id": Constants.categoryID,
            "localizedDescriptionKey": "Wallpaper Exchange",
            "localizedNameKey": "Wallpaper Exchange",
            "preferredOrder": -1000,
            "previewImage": thumbnailURL.absoluteString,
            "representativeAssetID": representativeAssetID,
            "subcategories": [
                [
                    "id": Constants.subcategoryID,
                    "localizedDescriptionKey": "Wallpaper Exchange",
                    "localizedNameKey": "Wallpaper Exchange",
                    "preferredOrder": -1000,
                    "previewImage": thumbnailURL.absoluteString,
                    "representativeAssetID": representativeAssetID,
                ],
            ],
        ]
    }

    private func shotID(for wallpaperID: Int) -> String {
        "WALLPAPER_EXCHANGE_\(wallpaperID)"
    }

    private func updateWallpaperStoreIndex(indexURL: URL, backupURL: URL, assetID: String, thumbnailURL: URL) throws {
        guard fm.fileExists(atPath: indexURL.path) else {
            throw AerialError.manifestUnavailable
        }
        let originalData = try Data(contentsOf: indexURL)
        if !fm.fileExists(atPath: backupURL.path) {
            try originalData.write(to: backupURL, options: .atomic)
        }

        guard var root = try PropertyListSerialization.propertyList(from: originalData, options: [], format: nil) as? [String: Any] else {
            throw AerialError.manifestUnavailable
        }

        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
        let aerialChoice: [String: Any] = [
            "Configuration": configuration,
            "Files": [],
            "Provider": "com.apple.wallpaper.choice.aerials",
        ]
        let imageChoice = try imageChoice(for: thumbnailURL)
        let now = Date()
        updateIdleNodes(in: &root, choice: aerialChoice, now: now)
        updateDesktopNodes(in: &root, choice: imageChoice, now: now)

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            try? originalData.write(to: indexURL, options: .atomic)
            throw AerialError.manifestUnavailable
        }
    }

    private func updateWallpaperStoreIndexForImage(indexURL: URL, backupURL: URL, imageURL: URL) throws {
        guard fm.fileExists(atPath: indexURL.path) else {
            throw AerialError.manifestUnavailable
        }
        let originalData = try Data(contentsOf: indexURL)
        if !fm.fileExists(atPath: backupURL.path) {
            try originalData.write(to: backupURL, options: .atomic)
        }

        guard var root = try PropertyListSerialization.propertyList(from: originalData, options: [], format: nil) as? [String: Any] else {
            throw AerialError.manifestUnavailable
        }

        let choice = try imageChoice(for: imageURL)
        let now = Date()
        updateIdleNodes(in: &root, choice: choice, now: now)
        updateDesktopNodes(in: &root, choice: choice, now: now)

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            try? originalData.write(to: indexURL, options: .atomic)
            throw AerialError.manifestUnavailable
        }
    }

    private func updateIdleNodes(in dictionary: inout [String: Any], choice: [String: Any], now: Date) {
        if var idle = dictionary["Idle"] as? [String: Any] {
            applyWallpaperChoice(to: &idle, choice: choice, now: now)
            dictionary["Idle"] = idle
        }

        for key in Array(dictionary.keys) {
            if var child = dictionary[key] as? [String: Any] {
                updateIdleNodes(in: &child, choice: choice, now: now)
                dictionary[key] = child
            } else if var array = dictionary[key] as? [[String: Any]] {
                for index in array.indices {
                    updateIdleNodes(in: &array[index], choice: choice, now: now)
                }
                dictionary[key] = array
            }
        }
    }

    private func updateDesktopNodes(in dictionary: inout [String: Any], choice: [String: Any], now: Date) {
        if var desktop = dictionary["Desktop"] as? [String: Any] {
            applyWallpaperChoice(to: &desktop, choice: choice, now: now)
            dictionary["Desktop"] = desktop
        }

        for key in Array(dictionary.keys) {
            if var child = dictionary[key] as? [String: Any] {
                updateDesktopNodes(in: &child, choice: choice, now: now)
                dictionary[key] = child
            } else if var array = dictionary[key] as? [[String: Any]] {
                for index in array.indices {
                    updateDesktopNodes(in: &array[index], choice: choice, now: now)
                }
                dictionary[key] = array
            }
        }
    }

    private func applyWallpaperChoice(to node: inout [String: Any], choice: [String: Any], now: Date) {
        var content = node["Content"] as? [String: Any] ?? [:]
        content["Choices"] = [choice]
        node["Content"] = content
        node["LastSet"] = now
        node["LastUse"] = now
    }

    private func imageChoice(for imageURL: URL) throws -> [String: Any] {
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: [
                "type": "imageFile",
                "url": ["relative": imageURL.absoluteString],
            ],
            format: .binary,
            options: 0
        )
        return [
            "Configuration": configuration,
            "Files": [],
            "Provider": "com.apple.wallpaper.choice.image",
        ]
    }

    private func applySystemWallpaperPointers(videoURL: URL, thumbnailURL: URL) throws {
        try writeDefault(
            domain: "com.apple.wallpaper",
            key: "SystemWallpaperURL",
            value: videoURL.absoluteString
        )
        try applyStaticLockScreenFallback(imageURL: thumbnailURL)
    }

    private func applyStaticLockScreenFallback(imageURL: URL) throws {
        try writeDefault(
            domain: "com.apple.loginwindow",
            key: "DesktopPicture",
            value: imageURL.path
        )
        writeLockScreenCacheImage(imageURL)
    }

    private func writeDefault(domain: String, key: String, value: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-string", value]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                logger.error("failed to write default \(domain, privacy: .public).\(key, privacy: .public): \(message, privacy: .public)")
                throw AerialError.manifestUnavailable
            }
        } catch let error as AerialError {
            throw error
        } catch {
            logger.error("failed to write default \(domain, privacy: .public).\(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AerialError.manifestUnavailable
        }
    }

    private func writeLockScreenCacheImage(_ imageURL: URL) {
        guard let userUUID = generatedUserUUID() else {
            logger.error("failed to resolve GeneratedUID for lock-screen cache")
            return
        }

        let directory = URL(fileURLWithPath: "/Library/Caches/Desktop Pictures", isDirectory: true)
            .appendingPathComponent(userUUID, isDirectory: true)
        let destination = directory.appendingPathComponent("lockscreen.png")

        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            if let image = NSImage(contentsOf: imageURL), try writePNG(image: image, to: destination) {
                logger.info("updated lock-screen cache image at \(destination.path, privacy: .public)")
            } else {
                try fm.copyItem(at: imageURL, to: destination)
                logger.info("copied lock-screen cache image at \(destination.path, privacy: .public)")
            }
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        } catch {
            logger.error("failed to update lock-screen cache image: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func generatedUserUUID() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "GeneratedUID"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .first(where: { $0.contains("GeneratedUID:") })?
                .split(separator: " ")
                .last
                .map(String.init)
        } catch {
            logger.error("failed to read GeneratedUID: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func restartAerialExtension() throws {
        let extensionPath = "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/MacOS/WallpaperAerialsExtension"
        guard fm.fileExists(atPath: extensionPath) else {
            throw AerialError.extensionUnavailable
        }

        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-f", "WallpaperAerialsExtension"]
        try? kill.run()
        kill.waitUntilExit()

        let start = Process()
        start.executableURL = URL(fileURLWithPath: extensionPath)
        do {
            try start.run()
            logger.info("restarted WallpaperAerialsExtension for lock-screen wallpaper")
        } catch {
            logger.error("failed to restart WallpaperAerialsExtension: \(error.localizedDescription, privacy: .public)")
            throw AerialError.extensionUnavailable
        }
    }
}
