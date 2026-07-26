import AppKit
import AVFoundation
import CoreVideo
import Foundation
import os.log

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
            case .restoreUnavailable:
                return L10n.settings.lockScreenRestoreUnavailable
            }
        }
    }

    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
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
        let storeIndex: URL
        let workingRoot: URL
        let backups: URL
        let currentMovie: URL
    }

    private enum DefaultsKey {
        static let managedAssetIDs = "wallpaper.lockScreen.managedAssetIDs"
    }

    private let logger = Logger(subsystem: "com.wallpaperexchange.mac", category: "aerial-lock-screen")
    private let fm = FileManager.default

    private init() {
        installWakeObservers()
    }

    var canRestoreOriginals: Bool {
        guard Self.isSupported, let paths = try? paths() else { return false }
        return !(backupURLs(in: paths.backups).isEmpty)
    }

    /// Converts the selected wallpaper into an Aerial-compatible movie, backs
    /// up every active lock-screen Aerial and atomically swaps the cached files.
    func apply(wallpaper: Wallpaper, sourceURL: URL, sourceIsVideo: Bool) async throws {
        guard Self.isSupported else { throw AerialError.unsupported }

        let paths = try paths()
        try ensureWorkingDirectories(paths)
        let assetIDs = try activeLockScreenAerialAssetIDs(from: paths.storeIndex)
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

        UserDefaults.standard.set(assetIDs, forKey: DefaultsKey.managedAssetIDs)
        restartWallpaperProcesses()
        logger.notice("applied lock-screen wallpaper id=\(wallpaper.id, privacy: .public) to \(assetIDs.count, privacy: .public) Aerial asset(s)")
    }

    /// Restores every Aerial file ever replaced by Wallpaper Exchange. Backups
    /// are only deleted after all originals have been put back successfully.
    func restoreOriginals() throws {
        guard Self.isSupported else { throw AerialError.unsupported }
        let paths = try paths()
        let backups = backupURLs(in: paths.backups)
        guard !backups.isEmpty else { throw AerialError.restoreUnavailable }

        for backup in backups {
            let assetID = backup.deletingPathExtension().lastPathComponent
            let destination = paths.videos.appendingPathComponent("\(assetID).mov")
            guard fm.isWritableFile(atPath: paths.videos.path) else {
                throw AerialError.permissionRequired
            }
            try replaceFileAtomically(source: backup, destination: destination)
        }

        for backup in backups {
            try? fm.removeItem(at: backup)
        }
        try? fm.removeItem(at: paths.currentMovie)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.managedAssetIDs)
        restartWallpaperProcesses()
        logger.notice("restored \(backups.count, privacy: .public) original Aerial asset(s)")
    }

    private func paths() throws -> Paths {
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AerialError.storeUnavailable
        }
        let systemRoot = appSupport.appendingPathComponent("com.apple.wallpaper", isDirectory: true)
        let workingRoot = appSupport.appendingPathComponent("WallpaperExchange/LockScreen", isDirectory: true)
        return Paths(
            videos: systemRoot.appendingPathComponent("aerials/videos", isDirectory: true),
            storeIndex: systemRoot.appendingPathComponent("Store/Index.plist"),
            workingRoot: workingRoot,
            backups: workingRoot.appendingPathComponent("Backups", isDirectory: true),
            currentMovie: workingRoot.appendingPathComponent("Current.mov")
        )
    }

    private func ensureWorkingDirectories(_ paths: Paths) throws {
        guard fm.fileExists(atPath: paths.storeIndex.path), fm.fileExists(atPath: paths.videos.path) else {
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

    private func activeLockScreenAerialAssetIDs(from indexURL: URL) throws -> [String] {
        guard fm.fileExists(atPath: indexURL.path) else { throw AerialError.storeUnavailable }
        let data = try Data(contentsOf: indexURL)
        let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        var idleIDs = Set<String>()
        collectAerialAssetIDs(in: root, sectionName: "Idle", output: &idleIDs)
        if !idleIDs.isEmpty { return idleIDs.sorted() }

        // Some macOS 26 builds store the screen-saver choice in a Linked node.
        var linkedIDs = Set<String>()
        collectAerialAssetIDs(in: root, sectionName: "Linked", output: &linkedIDs)
        return linkedIDs.sorted()
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

    private func exportVideo(source: URL, destination: URL) async throws {
        try? fm.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AerialError.exportUnavailable
        }
        exporter.outputURL = destination
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true

        let box = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let message = box.session.error?.localizedDescription ?? L10n.detail.lockScreenConversionFailed
                    continuation.resume(throwing: AerialError.conversionFailed(message))
                default:
                    continuation.resume(throwing: AerialError.conversionFailed(L10n.detail.lockScreenConversionFailed))
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
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyManagedMovieAfterWake() }
        }
        workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyManagedMovieAfterWake() }
        }
    }

    private func reapplyManagedMovieAfterWake() {
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
        if replaced > 0 { restartWallpaperProcesses() }
    }

    private func restartWallpaperProcesses() {
        for processName in ["WallpaperAgent", "WallpaperAerialsExtension", "legacyScreenSaver", "idleassetsd"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [processName]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
