import SwiftUI

// Replica of the web's .balance-pill — warm gradient capsule, 3D-feel
// minted-coin disc, mono tabular digits + small "COINS" caps label.
// Used in the sidebar identity footer and anywhere else we surface
// the signed-in balance.
struct BalancePill: View {
    let coins: Int
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            // Minted-coin disc — radial gradient hot → cool with
            // an inset highlight + drop shadow so it reads as a
            // physical object.
            ZStack {
                Circle().fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.90, blue: 0.55),
                            Color(red: 0.95, green: 0.62, blue: 0.30),
                            Color(red: 0.65, green: 0.32, blue: 0.18),
                        ],
                        center: .init(x: 0.35, y: 0.30),
                        startRadius: 0, endRadius: 14
                    )
                )
                Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.8).padding(0.5)
            }
            .frame(width: 18, height: 18)
            .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 1)
            .rotation3DEffect(.degrees(hover ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 0.72), value: hover)

            Text("\(coins)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ink)
                .monospacedDigit()

            Text("COINS")
                .font(.kicker).tracking(2.0)
                .foregroundStyle(Color.muted)
        }
        .padding(.leading, 9).padding(.trailing, 14)
        .frame(height: 36)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.96, blue: 0.92).opacity(0.92),
                        Color(red: 0.97, green: 0.91, blue: 0.85).opacity(0.92),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            Capsule().stroke(hover ? Color.accent : Color(red: 0.84, green: 0.74, blue: 0.62), lineWidth: 1)
        )
        .shadow(color: hover ? Color.accent.opacity(0.35) : Color.black.opacity(0.08),
                radius: hover ? 10 : 1, x: 0, y: hover ? 8 : 1)
        .offset(y: hover ? -2 : 0)
        .animation(.easeOut(duration: 0.22), value: hover)
        .onHover { hover = $0 }
    }
}
