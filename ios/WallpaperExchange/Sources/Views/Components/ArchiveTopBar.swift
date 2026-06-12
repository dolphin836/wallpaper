import SwiftUI

// Shared top toolbar for the four root tabs: collections drawer on the
// left, the page's serif title in the middle, and the global
// lock-screen-preview toggle on the right.
struct ArchiveTopBar: View {
    var title: String

    @Environment(UIPrefs.self) private var prefs
    @State private var showCollections = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showCollections = true
            } label: {
                Image(systemName: "square.stack")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.pressable)

            Spacer()

            // Script brand voice for the page title.
            Text(title)
                .font(.script(25))
                .foregroundStyle(Color.ink)
                .baselineOffset(-2)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    prefs.lockPreview.toggle()
                }
            } label: {
                Image(systemName: prefs.lockPreview ? "lock.iphone" : "iphone")
                    .font(.system(size: 15, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(prefs.lockPreview ? Color.black.opacity(0.82) : .white.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background {
                        if prefs.lockPreview {
                            Circle().fill(Color.accent)
                        } else {
                            Circle().fill(.white.opacity(0.08))
                        }
                    }
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.paper)
        .fullScreenCoverCompat(isPresented: $showCollections) {
            CollectionsBrowser()
        }
    }
}
