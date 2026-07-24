import SwiftUI

// Shared on-image wallpaper metadata tags. These mirror the web card tags:
// resolution is a compact charcoal spec plate, live media uses the
// brand-orange capsule, and Mac-only dynamic media uses a cool-blue capsule.
// A fixed height keeps text and optional icons on the same optical centre line
// in every grid implementation.
struct WallpaperCardTag: View {
    enum Kind {
        case resolution
        case live
        case mac
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
        case .live, .mac:
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
        case .mac:
            Capsule(style: .continuous)
                .fill(Color(red: 0.13, green: 0.39, blue: 0.68).opacity(0.94))
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
        case .mac:
            Capsule(style: .continuous)
                .strokeBorder(Color(red: 0.52, green: 0.76, blue: 0.96).opacity(0.82), lineWidth: 1)
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .resolution: Color.black.opacity(0.16)
        case .live: Color.accent.opacity(0.22)
        case .mac: Color(red: 0.13, green: 0.39, blue: 0.68).opacity(0.24)
        }
    }
}
