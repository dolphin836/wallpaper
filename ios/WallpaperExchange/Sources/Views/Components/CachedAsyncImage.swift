import SwiftUI
import UIKit
import ImageIO
import CryptoKit

// UIKit port of the Mac client's CachedAsyncImage: in-memory cache of
// *decoded* UIImage instances over a shared on-disk byte cache. Decoded
// caching avoids the re-decode flash when grid rows recycle; the disk
// layer keeps relaunches off the network entirely.
@MainActor
final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSString, UIImage>()
    private let dataLoader = ImageDataLoader()

    private init() {
        cache.countLimit = 160
        // Phone tiles are decoded much smaller than the Mac's 1800px
        // ceiling, so the same budget holds many more entries.
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func get(_ url: URL, maxPixelDimension: Int) -> UIImage? {
        cache.object(forKey: cacheKey(for: url, maxPixelDimension: maxPixelDimension))
    }

    func load(_ url: URL, maxPixelDimension: Int) async -> UIImage? {
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

    nonisolated private static func downsample(data: Data, maxPixelDimension: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private func estimatedCost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else {
            return Int(image.size.width * image.size.height * 4)
        }
        return max(1, cg.width * cg.height * 4)
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

    @State private var uiImage: UIImage?
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
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
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
            self.uiImage = img
            loadedURL = requestURL
            onLoad?()
        }
    }
}
