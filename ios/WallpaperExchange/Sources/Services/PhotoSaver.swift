import Foundation
import Photos


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
    static func save(remoteURL: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw PhotoSaverError.saveFailed
        }
        try await save(imageData: data)
    }

    static func save(imageData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaverError.accessDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
            }
        } catch {
            throw PhotoSaverError.saveFailed
        }
    }
}
