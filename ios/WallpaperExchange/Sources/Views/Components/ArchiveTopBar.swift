import SwiftUI

// Shared top toolbar for the four root tabs: collections drawer on the
// left, the page's serif title in the middle, and the global
// lock-screen-preview toggle on the right.
struct ArchiveTopBar: View {
    var title: String

    @Environment(UIPrefs.self) private var prefs
    @State private var showCollections = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    showCollections = true
                } label: {
                    Image(systemName: "square.stack")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 34, height: 34)
                        .background(Color.paper2, in: Circle())
                        .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
                }
                .buttonStyle(.pressable)

                Spacer()

                Text(title)
                    .font(.display22)
                    .foregroundStyle(Color.ink)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        prefs.lockPreview.toggle()
                    }
                } label: {
                    Image(systemName: prefs.lockPreview ? "lock.iphone" : "iphone")
                        .font(.system(size: 15, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(prefs.lockPreview ? Color.accentInk : Color.ink2)
                        .frame(width: 34, height: 34)
                        .background(prefs.lockPreview ? Color.accentSoft : Color.paper2, in: Circle())
                        .overlay(
                            Circle().strokeBorder(
                                prefs.lockPreview ? Color.accent.opacity(0.45) : Color.hair,
                                lineWidth: 1)
                        )
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Hairline under the bar separates chrome from the scroll
            // surface without adding weight.
            Rectangle()
                .fill(Color.hair.opacity(0.55))
                .frame(height: 1)
        }
        .background(Color.paper)
        .fullScreenCoverCompat(isPresented: $showCollections) {
            CollectionsBrowser()
        }
    }
}
