import SwiftUI
import AppKit

// In-memory cache of *decoded* NSImage instances keyed by URL. SwiftUI's
// AsyncImage relies on URLCache, which still re-decodes on each appearance —
// in a LazyVStack that recycles rows on scroll, that produced a visible
// loading flash every time a row came back into view. Caching the decoded
// image bypasses both the network and the decoder.
@MainActor
final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 300 // ~300 distinct URLs, generous for a menubar feed
    }

    func get(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Drop-in replacement for AsyncImage that consults ImageCacheStore before
/// hitting the network. `onLoad` fires once the image is available (cache hit
/// or network), useful for triggering progressive-load fade transitions.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let onLoad: (() -> Void)?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var nsImage: NSImage?

    init(
        url: URL?,
        onLoad: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
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
        guard let url else { return }

        // Cache hit — instant, no flash.
        if let cached = ImageCacheStore.shared.get(url) {
            if self.nsImage !== cached {
                self.nsImage = cached
            }
            onLoad?()
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let img = NSImage(data: data) {
                ImageCacheStore.shared.set(img, for: url)
                self.nsImage = img
                onLoad?()
            }
        } catch {
            // Silent — the placeholder stays visible on failure.
        }
    }
}
