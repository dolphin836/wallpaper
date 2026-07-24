import SwiftUI

// Shared on-image wallpaper metadata tags. These mirror the web card tags:
// resolution is a compact charcoal spec plate, while live media uses the
// brand-orange capsule. A fixed height keeps text and optional icons on the
// same optical centre line in every grid implementation.
struct WallpaperCardTag: View {
    enum Kind {
        case resolution
        case live
    }

    let text: String
    let kind: Kind
    var icon: String? = nil

    init(_ text: String, kind: Kind, icon: String? = nil) {
        self.text = text
        self.kind = kind
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: icon == nil ? 0 : 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(textFont)
                .tracking(kind == .resolution ? 0.4 : 0.1)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(0.97))
        .padding(.leading, kind == .resolution ? 6 : 5)
        .padding(.trailing, kind == .resolution ? 6 : 7)
        .frame(height: 20, alignment: .center)
        .background { backgroundShape }
        .overlay { borderShape }
        .shadow(color: shadowColor, radius: 4, y: 2)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var textFont: Font {
        switch kind {
        case .resolution:
            return .system(size: 9, weight: .semibold, design: .monospaced)
        case .live:
            return .system(size: 9, weight: .semibold)
        }
    }

    @ViewBuilder private var backgroundShape: some View {
        switch kind {
        case .resolution:
            let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
            ZStack {
                shape.fill(.thinMaterial)
                shape.fill(Color(red: 0.055, green: 0.070, blue: 0.078).opacity(0.78))
            }
            .environment(\.colorScheme, .dark)
        case .live:
            Capsule(style: .continuous)
                .fill(Color.accent.blended(
                    with: Color(red: 0.17, green: 0.055, blue: 0.015),
                    fraction: 0.18
                ))
        }
    }

    @ViewBuilder private var borderShape: some View {
        switch kind {
        case .resolution:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        case .live:
            Capsule(style: .continuous)
                .strokeBorder(Color.accent.blended(with: .white, fraction: 0.24), lineWidth: 1)
        }
    }

    private var shadowColor: Color {
        kind == .resolution ? Color.black.opacity(0.16) : Color.accent.opacity(0.22)
    }
}
