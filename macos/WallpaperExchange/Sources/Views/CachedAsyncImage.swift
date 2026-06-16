import SwiftUI
import AppKit
import ImageIO
import CryptoKit

// In-memory cache of *decoded* NSImage instances keyed by URL. SwiftUI's
// AsyncImage relies on URLCache, which still re-decodes on each appearance —
// in a LazyVStack that recycles rows on scroll, that produced a visible
// loading flash every time a row came back into view. Caching the decoded
// image bypasses both the network and the decoder.
@MainActor
final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSString, NSImage>()
    private let dataLoader = ImageDataLoader()

    private init() {
        cache.countLimit = 140
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func get(_ url: URL, maxPixelDimension: Int) -> NSImage? {
        cache.object(forKey: cacheKey(for: url, maxPixelDimension: maxPixelDimension))
    }

    func load(_ url: URL, maxPixelDimension: Int) async -> NSImage? {
        if let cached = get(url, maxPixelDimension: maxPixelDimension) {
            return cached
        }

        do {
            let data = try await dataLoader.data(for: url)
            let image = await Task.detached(priority: .utility) {
                Self.downsample(data: data, maxPixelDimension: maxPixelDimension)
            }.value
            guard let image else {
                return nil
            }
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

    nonisolated private static func downsample(data: Data, maxPixelDimension: Int) -> NSImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return NSImage(data: data)
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func estimatedCost(of image: NSImage) -> Int {
        if let pixels = image.representations
            .map({ max($0.pixelsWide, 0) * max($0.pixelsHigh, 0) })
            .max(), pixels > 0 {
            return max(1, pixels * 4)
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(1, Int(image.size.width * scale) * Int(image.size.height * scale))
        return pixels * 4
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

// Disk layer under the in-memory cache: raw downloaded bytes keyed by a
// SHA-256 of the URL, in ~/Library/Caches so the system may purge it.
// Without it every launch re-downloads the full grid (50+ tiles). Disk
// hits still pay the decode, but skip the network entirely.
private actor ImageDiskCache {
    static let shared = ImageDiskCache()

    private let dir: URL
    private let maxAge: TimeInterval = 7 * 24 * 3600
    private let maxBytes = 256 * 1024 * 1024
    private var didCleanup = false

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("WallpaperExchange/ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func data(for url: URL) -> Data? {
        cleanupIfNeeded()
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Touch so the size-cap eviction below behaves as LRU.
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

/// Drop-in replacement for AsyncImage that consults ImageCacheStore before
/// hitting the network. `onLoad` fires once the image is available (cache hit
/// or network), useful for triggering progressive-load fade transitions.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixelDimension: Int
    let onLoad: (() -> Void)?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var nsImage: NSImage?
    @State private var loadedURL: URL?

    init(
        url: URL?,
        maxPixelDimension: Int = 1800,
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
        ZStack {
            if let nsImage {
                content(Image(nsImage: nsImage))
            } else {
                placeholder()
                if url != nil {
                    ImageLoadingBeam()
                }
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            nsImage = nil
            loadedURL = nil
            return
        }

        if loadedURL != url {
            nsImage = nil
            loadedURL = nil
        }

        // Cache hit — instant, no flash.
        if let cached = ImageCacheStore.shared.get(url, maxPixelDimension: maxPixelDimension) {
            if self.nsImage !== cached {
                self.nsImage = cached
            }
            loadedURL = url
            onLoad?()
            return
        }

        let requestURL = url
        if let img = await ImageCacheStore.shared.load(requestURL, maxPixelDimension: maxPixelDimension) {
            guard !Task.isCancelled, self.url == requestURL else { return }
            self.nsImage = img
            loadedURL = requestURL
            onLoad?()
        }
    }
}

private struct ImageLoadingBeam: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let bandWidth = max(width * 0.58, 72)

            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceMotion {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: Color.white.opacity(0.34), location: 0.50),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: bandWidth, height: height * 1.7)
                        .rotationEffect(.degrees(14))
                        .offset(x: sweep ? width + bandWidth : -bandWidth, y: 0)
                        .blendMode(.plusLighter)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
            .onDisappear {
                sweep = false
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
