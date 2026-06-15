import SwiftUI

// Shared top toolbar for the four root tabs: collections drawer on the
// left, the page's title in the middle, and the global lock-screen-
// preview toggle on the right.
struct ArchiveTopBar: View {
    var title: String

    @Environment(UIPrefs.self) private var prefs
    @Environment(AuthService.self) private var auth
    @Environment(TabRouter.self) private var router

    var body: some View {
        HStack(spacing: 10) {
            avatarButton

            Text(title)
                .font(.script(27))
                .foregroundStyle(Color.ink)
                .baselineOffset(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            LockPreviewToolbarButton()
        }
        .frame(height: 52)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.paper2.opacity(0.36), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hair.opacity(0.78), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var avatarButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                router.selection = 4
            }
        } label: {
            ZStack {
                if let user = auth.user, !user.avatarURL.isEmpty {
                    CachedAsyncImage(url: URL(string: user.avatarURL), maxPixelDimension: 180) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarFallback
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(L10n.strings(for: prefs.language).me)
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.paper3.opacity(0.78))
            .overlay {
                if let user = auth.user {
                    Text(String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink2)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ink2)
                }
            }
    }

}

struct LockPreviewToolbarButton: View {
    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                prefs.lockPreview.toggle()
            }
        } label: {
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
        .accessibilityLabel(L10n.strings(for: prefs.language).lockPreview)
        .archiveSelectionFeedback(trigger: prefs.lockPreview)
    }

    private var icon: String {
        prefs.lockPreview ? "lock.iphone" : "iphone"
    }

    private var selected: Bool {
        prefs.lockPreview
    }
}
