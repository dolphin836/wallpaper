import SwiftUI

// Pulsing paper placeholder — the archive's skeleton vocabulary
// (paper-3 fills, no shimmer gradients).
struct SkeletonBlock: View {
    var radius: CGFloat = 12

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.paper3)
            .opacity(pulse ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ImageLoadingVeil: View {
    enum Strength {
        case whisper
        case card
        case detail

        var baseOpacity: Double {
            switch self {
            case .whisper: return 0.05
            case .card: return 0.08
            case .detail: return 0.10
            }
        }

        var sweepOpacity: Double {
            switch self {
            case .whisper: return 0.10
            case .card: return 0.15
            case .detail: return 0.18
            }
        }
    }

    var strength: Strength = .card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sweepWidth = max(width * 0.58, 72)

            ZStack {
                LinearGradient(
                    colors: [
                        .white.opacity(strength.baseOpacity * 0.35),
                        .white.opacity(strength.baseOpacity),
                        .white.opacity(strength.baseOpacity * 0.35),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(pulse ? 1 : 0.58)

                if !reduceMotion {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(strength.sweepOpacity), location: 0.48),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: sweepWidth)
                        .rotationEffect(.degrees(17))
                        .offset(x: sweep ? width + sweepWidth : -sweepWidth)
                        .blendMode(.screen)
                }
            }
            .animation(
                .easeInOut(duration: 1.35).repeatForever(autoreverses: true),
                value: pulse
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.85).repeatForever(autoreverses: false),
                value: sweep
            )
            .onAppear {
                pulse = true
                sweep = true
            }
            .onDisappear {
                pulse = false
                sweep = false
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LoadingCoverImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var maxPixelDimension: Int = 900
    var veilStrength: ImageLoadingVeil.Strength = .card
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loaded = false
    @State private var failed = false

    init(
        url: URL?,
        maxPixelDimension: Int = 900,
        veilStrength: ImageLoadingVeil.Strength = .card,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelDimension = maxPixelDimension
        self.veilStrength = veilStrength
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            CachedAsyncImage(
                url: url,
                maxPixelDimension: maxPixelDimension,
                onLoad: {
                    withAnimation(.easeOut(duration: 0.22)) {
                        loaded = true
                    }
                },
                onFailure: {
                    failed = true
                }
            ) { image in
                content(image)
            } placeholder: {
                placeholder()
            }

            if url != nil && !loaded && !failed {
                ImageLoadingVeil(strength: veilStrength)
                    .transition(.opacity)
            }
        }
        .onChange(of: url) { _, _ in
            loaded = false
            failed = false
        }
    }
}

// Mirrors WallpaperGrid's two-column geometry — uniform device-ratio
// tiles — so the page doesn't reflow when real tiles land.
struct WallpaperGridSkeleton: View {
    var count: Int = 6

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonBlock()
                    .aspectRatio(DeviceScreenRatio.value, contentMode: .fit)
            }
        }
        .padding(.horizontal, 12)
    }
}

// Horizontal rail placeholder for the Home shelves.
struct RailSkeleton: View {
    var height: CGFloat = 190

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    SkeletonBlock()
                        .frame(width: height * [0.72, 1.5, 0.8][i], height: height)
                }
            }
            .padding(.horizontal, 12)
        }
        .disabled(true)
    }
}

// Standard empty state: kicker over muted line, generous breathing room.
struct EmptyStateView: View {
    var kicker: String
    var message: String

    var body: some View {
        VStack(spacing: 6) {
            Kicker(text: kicker)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
