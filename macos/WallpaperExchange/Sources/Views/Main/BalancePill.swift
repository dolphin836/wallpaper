import SwiftUI

extension Color {
    static let coinSurfaceStart = Color.adaptiveRGBA(
        light: (0.990, 0.960, 0.920, 0.94),
        dark:  (0.150, 0.102, 0.066, 0.95)
    )
    static let coinSurfaceEnd = Color.adaptiveRGBA(
        light: (0.970, 0.910, 0.850, 0.94),
        dark:  (0.070, 0.056, 0.046, 0.95)
    )
    static let coinBorder = Color.adaptiveRGBA(
        light: (0.840, 0.740, 0.620, 1.00),
        dark:  (0.940, 0.560, 0.260, 0.36)
    )
    static let coinValue = Color.adaptive(
        light: (0.176, 0.170, 0.164),
        dark:  (1.000, 0.760, 0.500)
    )
    static let coinLabel = Color.adaptive(
        light: (0.524, 0.516, 0.504),
        dark:  (0.760, 0.620, 0.470)
    )
    static let coinGoldTop = Color.adaptive(
        light: (1.000, 0.900, 0.550),
        dark:  (1.000, 0.780, 0.390)
    )
    static let coinGoldMid = Color.adaptive(
        light: (0.950, 0.620, 0.300),
        dark:  (0.950, 0.450, 0.130)
    )
    static let coinGoldBottom = Color.adaptive(
        light: (0.650, 0.320, 0.180),
        dark:  (0.410, 0.160, 0.070)
    )
    static let coinGlyph = Color.adaptiveRGBA(
        light: (1.000, 0.985, 0.930, 0.92),
        dark:  (1.000, 0.870, 0.640, 0.90)
    )
    static let coinGlow = Color.adaptiveRGBA(
        light: (0.886, 0.491, 0.282, 0.35),
        dark:  (1.000, 0.435, 0.155, 0.42)
    )
}

struct CoinDisc: View {
    var size: CGFloat = 18
    var showSymbol: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(
                RadialGradient(
                    colors: [.coinGoldTop, .coinGoldMid, .coinGoldBottom],
                    center: .init(x: 0.35, y: 0.30),
                    startRadius: 0,
                    endRadius: max(12, size * 0.78)
                )
            )
            Circle()
                .stroke(Color.coinGlyph.opacity(0.48), lineWidth: max(0.7, size / 24))
                .padding(0.5)
            if showSymbol {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: max(9, size * 0.38), weight: .semibold))
                    .foregroundStyle(Color.coinGlyph)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.22), radius: max(1, size / 18), x: 0, y: 1)
    }
}

struct MiniCoinPill: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 6) {
            CoinDisc(size: 16)
            Text("\(coins)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.coinValue)
                .monospacedDigit()
            Text("COINS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.coinLabel)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [.coinSurfaceStart, .coinSurfaceEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(Capsule().strokeBorder(Color.coinBorder, lineWidth: 1))
    }
}

// Replica of the web's .balance-pill — warm gradient capsule, 3D-feel
// minted-coin disc, mono tabular digits + small "COINS" caps label.
// Used in the sidebar identity footer and anywhere else we surface
// the signed-in balance.
struct BalancePill: View {
    let coins: Int
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            CoinDisc(size: 18)
            .rotation3DEffect(.degrees(hover ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 0.72), value: hover)

            Text("\(coins)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.coinValue)
                .monospacedDigit()

            Text("COINS")
                .font(.kicker).tracking(2.0)
                .foregroundStyle(Color.coinLabel)
        }
        .padding(.leading, 9).padding(.trailing, 14)
        .frame(height: 36)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [.coinSurfaceStart, .coinSurfaceEnd],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            Capsule().stroke(hover ? Color.accent : Color.coinBorder, lineWidth: 1)
        )
        .shadow(color: hover ? Color.coinGlow : Color.black.opacity(0.12),
                radius: hover ? 10 : 1, x: 0, y: hover ? 8 : 1)
        .offset(y: hover ? -2 : 0)
        .animation(.easeOut(duration: 0.22), value: hover)
        .onHover { hover = $0 }
    }
}
