import SwiftUI
import AppKit
import ImageIO

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
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
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
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage))
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
