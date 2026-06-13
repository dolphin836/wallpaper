import SwiftUI

// Shared top toolbar for the four root tabs: collections drawer on the
// left, the page's serif title in the middle, and the global
// lock-screen-preview toggle on the right.
struct ArchiveTopBar: View {
    var title: String

    @Environment(UIPrefs.self) private var prefs
    @State private var showCollections = false

    var body: some View {
        HStack(spacing: 10) {
            topButton(icon: "square.stack", selected: false) {
                showCollections = true
            }

            Text(title)
                .font(.script(27))
                .foregroundStyle(Color.ink)
                .baselineOffset(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            topButton(icon: prefs.lockPreview ? "lock.iphone" : "iphone", selected: prefs.lockPreview) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    prefs.lockPreview.toggle()
                }
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.paper2.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hair.opacity(0.78), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            Color.paper
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.hair.opacity(0.45))
                        .frame(height: 1)
                }
        )
        .archiveSelectionFeedback(trigger: prefs.lockPreview)
        .fullScreenCoverCompat(isPresented: $showCollections) {
            CollectionsBrowser()
        }
    }

    private func topButton(icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(selected ? Color.black.opacity(0.82) : Color.ink2)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(selected ? Color.accent : Color.paper3.opacity(0.74))
                }
                .overlay(Circle().strokeBorder(selected ? Color.accent.opacity(0.55) : Color.hair, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
