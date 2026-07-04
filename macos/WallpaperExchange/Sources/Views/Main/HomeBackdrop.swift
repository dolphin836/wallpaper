import SwiftUI

// Backdrop source for the Home page. HomeView publishes the current
// weekly hero (dominant color + thumb + original URLs) after its fetch;
// MainWindow renders HomeBackdropView at the window root whenever Home
// is the active top-level page, so the wallpaper fills the entire
// window behind the glass chrome.
@MainActor
@Observable
final class HomeBackdropEnv {
    static let shared = HomeBackdropEnv()

    private(set) var dominantColor: String?
    private(set) var thumbURL: URL?
    private(set) var originalURL: URL?

    var hasContent: Bool {
        dominantColor != nil || thumbURL != nil || originalURL != nil
    }

    func set(dominant: String?, thumb: String?, original: String?) {
        dominantColor = (dominant?.isEmpty == false) ? dominant : nil
        thumbURL = Self.url(thumb)
        originalURL = Self.url(original)
    }

    private static func url(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}

// Full-window wallpaper backdrop with the same progressive order the
// detail page uses: default mesh (below this view) → dominant color →
// low-res thumb (blurred while upgrading) → full original.
struct HomeBackdropView: View {
    @State private var env = HomeBackdropEnv.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let dominant = env.dominantColor {
                    Color(hex: dominant).opacity(0.55)
                }

                if env.thumbURL != nil || env.originalURL != nil {
                    ProgressiveCachedAsyncImage(
                        lowURL: env.thumbURL,
                        highURL: env.originalURL ?? env.thumbURL,
                        lowMaxPixelDimension: 640,
                        highMaxPixelDimension: 2800
                    ) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }

                // Legibility scrim: darken the chrome row and the lower
                // half where the hero overlay text sits. The content
                // sections carry their own glass panel, so this stays
                // deliberately light.
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.34), location: 0),
                        .init(color: Color.black.opacity(0.06), location: 0.28),
                        .init(color: Color.black.opacity(0.10), location: 0.62),
                        .init(color: Color.black.opacity(0.42), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.42), value: env.dominantColor)
    }
}
