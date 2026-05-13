import Foundation
import AppKit

@MainActor
@Observable
final class WallpaperManager {
    static let shared = WallpaperManager()

    private(set) var downloadedIDs: Set<Int> = []
    private(set) var downloading: Set<Int> = []

    private let storageDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("WallpaperExchange/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        scanLocalFiles()
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
        defer { downloading.remove(wallpaper.id) }

        let remoteURL = try await APIClient.shared.getDownloadURL(wallpaperID: wallpaper.id)

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        let ext = Self.fileExtension(from: response, url: remoteURL, fallback: wallpaper.fileType)
        let dest = storageDir.appendingPathComponent("\(wallpaper.id).\(ext)")

        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempURL, to: dest)

        downloadedIDs.insert(wallpaper.id)
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
    }

    func deleteLocal(_ wallpaperID: Int) {
        if let url = localURL(for: wallpaperID) {
            try? FileManager.default.removeItem(at: url)
        }
        downloadedIDs.remove(wallpaperID)
    }

    private func scanLocalFiles() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = Int(name) {
                downloadedIDs.insert(id)
            }
        }
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
