import Foundation
import Photos
import UniformTypeIdentifiers


enum PhotoSaverError: LocalizedError {
    case accessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Photo library access was denied. Allow it in Settings to save wallpapers."
        case .saveFailed: return "Could not save the wallpaper to your photo library."
        }
    }
}

// iOS has no public API to set the device wallpaper, so "download" lands
// the full-resolution file in the photo library (add-only permission)
// and the user applies it from Photos / lock-screen customization —
// the same flow every wallpaper app on the platform uses.
enum PhotoSaver {
    static func fetchData(remoteURL: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw PhotoSaverError.saveFailed
        }
        return data
    }

    static func save(remoteURL: URL) async throws {
        let data = try await fetchData(remoteURL: remoteURL)
        try await save(imageData: data, sourceURL: remoteURL)
    }

    static func save(imageData: Data) async throws {
        try await save(imageData: imageData, sourceURL: nil)
    }

    static func save(imageData: Data, sourceURL: URL) async throws {
        try await save(imageData: imageData, sourceURL: Optional(sourceURL))
    }

    private static func save(imageData: Data, sourceURL: URL?) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaverError.accessDenied
        }

        let fileURL = try temporaryImageFile(for: imageData, sourceURL: sourceURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                options.uniformTypeIdentifier = uniformTypeIdentifier(for: fileURL)
                request.addResource(with: .photo, fileURL: fileURL, options: options)
            }
        } catch {
            throw PhotoSaverError.saveFailed
        }
    }

    private static func temporaryImageFile(for data: Data, sourceURL: URL?) throws -> URL {
        let ext = preferredImageExtension(for: data, sourceURL: sourceURL)
        let filename = "wallpaper-\(UUID().uuidString).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func preferredImageExtension(for data: Data, sourceURL: URL?) -> String {
        if let ext = sourceURL?.pathExtension.lowercased(),
           ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
            return ext == "jpeg" ? "jpg" : ext
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        return "jpg"
    }

    private static func uniformTypeIdentifier(for fileURL: URL) -> String? {
        UTType(filenameExtension: fileURL.pathExtension)?.identifier
    }
}

enum DownloadedWallpaperStore {
    private static let filePrefix = "wallpaper-"

    static func isDownloaded(_ wallpaperID: Int) -> Bool {
        guard let dir = try? downloadsDirectory(create: false),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }
        let prefix = localPrefix(wallpaperID)
        return files.contains { $0.lastPathComponent.hasPrefix(prefix) }
    }

    static func save(wallpaperID: Int, data: Data, sourceURL: URL) throws {
        let dir = try downloadsDirectory(create: true)
        removeExisting(wallpaperID)
        let ext = sanitizedExtension(from: sourceURL)
        let url = dir.appendingPathComponent("\(localPrefix(wallpaperID))\(ext)", isDirectory: false)
        try data.write(to: url, options: [.atomic])
    }

    private static func removeExisting(_ wallpaperID: Int) {
        guard let dir = try? downloadsDirectory(create: false),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }
        let prefix = localPrefix(wallpaperID)
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func downloadsDirectory(create: Bool) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let dir = base.appendingPathComponent("WallpaperExchange/Downloads", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func localPrefix(_ wallpaperID: Int) -> String {
        "\(filePrefix)\(wallpaperID)."
    }

    private static func sanitizedExtension(from sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        let allowed = CharacterSet.alphanumerics
        let cleaned = String(ext.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "bin" : cleaned
    }
}
