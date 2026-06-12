import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import ImageIO
import CryptoKit

// UIKit port of the Mac client's CachedAsyncImage: in-memory cache of
// *decoded* PlatformImage instances over a shared on-disk byte cache. Decoded
// caching avoids the re-decode flash when grid rows recycle; the disk
// layer keeps relaunches off the network entirely.
@MainActor
final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSString, PlatformImage>()
    private let dataLoader = ImageDataLoader()

    private init() {
        cache.countLimit = 140
        // Tiles decode at up to 1400px long side (device-ratio cells are
        // ~1200px tall on 3x phones), so give the decoded cache enough
        // room that scrolling back doesn't re-decode every screen.
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func get(_ url: URL, maxPixelDimension: Int) -> PlatformImage? {
        cache.object(forKey: cacheKey(for: url, maxPixelDimension: maxPixelDimension))
    }

    func load(_ url: URL, maxPixelDimension: Int) async -> PlatformImage? {
        if let cached = get(url, maxPixelDimension: maxPixelDimension) {
            return cached
        }
        do {
            let data = try await dataLoader.data(for: url)
            let image = await Task.detached(priority: .utility) {
                Self.downsample(data: data, maxPixelDimension: maxPixelDimension)
            }.value
            guard let image else { return nil }
            cache.setObject(
                image,
                forKey: cacheKey(for: url, maxPixelDimension: maxPixelDimension),
                cost: estimatedCost(of: image)
            )
            return image
        } catch {
            return nil
        }
    }

    private func cacheKey(for url: URL, maxPixelDimension: Int) -> NSString {
        "\(url.absoluteString)#px=\(maxPixelDimension)" as NSString
    }

    nonisolated private static func downsample(data: Data, maxPixelDimension: Int) -> PlatformImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return PlatformImage(data: data)
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return PlatformImage(data: data)
        }
        #if canImport(UIKit)
        return PlatformImage(cgImage: cgImage)
        #else
        return PlatformImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    private func estimatedCost(of image: PlatformImage) -> Int {
        let pixels = image.pixelSize
        return max(1, Int(pixels.width) * Int(pixels.height) * 4)
    }
}

private actor ImageDataLoader {
    private var inFlight: [URL: Task<Data, Error>] = [:]

    func data(for url: URL) async throws -> Data {
        if let task = inFlight[url] {
            return try await task.value
        }
        let task = Task<Data, Error> {
            if let cached = await ImageDiskCache.shared.data(for: url) {
                return cached
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            await ImageDiskCache.shared.store(data, for: url)
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }
}

// Raw downloaded bytes keyed by SHA-256 of the URL, in Caches so iOS may
// purge under pressure. 7-day TTL + LRU size cap pruned once per launch.
private actor ImageDiskCache {
    static let shared = ImageDiskCache()

    private let dir: URL
    private let maxAge: TimeInterval = 7 * 24 * 3600
    private let maxBytes = 192 * 1024 * 1024
    private var didCleanup = false

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func data(for url: URL) -> Data? {
        cleanupIfNeeded()
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    func store(_ data: Data, for url: URL) {
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name)
    }

    private func cleanupIfNeeded() {
        guard !didCleanup else { return }
        didCleanup = true

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var entries: [(url: URL, date: Date, size: Int)] = []
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            guard let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let date = values.contentModificationDate
            else { continue }
            if date < cutoff {
                try? fm.removeItem(at: file)
                continue
            }
            entries.append((file, date, values.fileSize ?? 0))
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }
}

/// Drop-in replacement for AsyncImage that consults ImageCacheStore
/// before hitting the network.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixelDimension: Int
    let onLoad: (() -> Void)?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: PlatformImage?
    @State private var loadedURL: URL?

    init(
        url: URL?,
        maxPixelDimension: Int = 900,
        onLoad: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelDimension = maxPixelDimension
        self.onLoad = onLoad
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(platformImage: uiImage))
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            uiImage = nil
            loadedURL = nil
            return
        }
        if loadedURL != url {
            uiImage = nil
            loadedURL = nil
        }
        if let cached = ImageCacheStore.shared.get(url, maxPixelDimension: maxPixelDimension) {
            if self.uiImage !== cached {
                self.uiImage = cached
            }
            loadedURL = url
            onLoad?()
            return
        }
        let requestURL = url
        if let img = await ImageCacheStore.shared.load(requestURL, maxPixelDimension: maxPixelDimension) {
            guard !Task.isCancelled, self.url == requestURL else { return }
            // Network/disk loads cross-fade in; memory-cache hits above
            // stay instant so scroll-back doesn't flicker.
            withAnimation(.easeOut(duration: 0.22)) {
                self.uiImage = img
            }
            loadedURL = requestURL
            onLoad?()
        }
    }
}
