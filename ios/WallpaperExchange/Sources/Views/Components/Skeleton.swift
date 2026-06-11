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

// Mirrors WallpaperGrid's two-column geometry so the page doesn't
// reflow when real tiles land.
struct WallpaperGridSkeleton: View {
    var count: Int = 6

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]
    private let ratios: [CGFloat] = [0.7, 1.5, 0.8, 0.66, 1.2, 0.75]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                SkeletonBlock()
                    .aspectRatio(ratios[i % ratios.count], contentMode: .fit)
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
