import SwiftUI

// iOS lock-screen mock drawn over a wallpaper: date line + clock up
// top, flashlight/camera pills at the bottom. `compact` scales the
// chrome down to grid-tile size.
struct LockScreenOverlay: View {
    var compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: compact ? 0 : 2) {
                Text(Self.dateString)
                    .font(.system(size: compact ? 7 : 15, weight: .medium))
                    .opacity(0.92)
                Text(Self.timeString)
                    .font(.system(size: compact ? 26 : 64, weight: .semibold, design: .rounded))
            }
            .padding(.top, compact ? 12 : 48)

            Spacer()

            HStack {
                bottomPill("flashlight.on.fill")
                Spacer()
                bottomPill("camera.fill")
            }
            .padding(.horizontal, compact ? 10 : 36)
            .padding(.bottom, compact ? 10 : 28)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: compact ? 2 : 6, y: 1)
        .allowsHitTesting(false)
    }

    private func bottomPill(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: compact ? 8 : 18, weight: .medium))
            .frame(width: compact ? 18 : 46, height: compact ? 18 : 46)
            .background(.black.opacity(0.35), in: Circle())
    }

    private static var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private static var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}
