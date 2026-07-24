import SwiftUI

// Full-window image viewer used by DetailPage. It mirrors the web viewer's
// zoom / rotate / reset controls and adds Mac-specific Plain / Home / Lock
// previews without changing the downloaded image itself.
struct FullscreenWallpaperPreview: View {
    let lowURL: URL?
    let highURL: URL?
    let title: String
    let metadata: String
    let onClose: () -> Void

    private enum Mode: String, CaseIterable {
        case plain
        case home
        case lock

        var label: String {
            switch self {
            case .plain: L10n.detail.previewPlain
            case .home: L10n.detail.previewHome
            case .lock: L10n.detail.previewLock
            }
        }
    }

    @State private var mode: Mode = .plain
    @State private var scale: CGFloat = 1
    @State private var rotation = 0.0
    @State private var pan: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveDrag: CGSize = .zero
    @FocusState private var keyboardFocused: Bool
    @Namespace private var modeNamespace

    private var renderedScale: CGFloat {
        min(5, max(0.5, scale * liveMagnification))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                wallpaper(size: proxy.size)

                if mode == .home {
                    homeScreenOverlay(size: proxy.size)
                        .transition(.opacity)
                } else if mode == .lock {
                    lockScreenOverlay(size: proxy.size)
                        .transition(.opacity)
                }

                viewerChrome(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onChange(of: mode) { _, _ in resetView() }
        .onAppear {
            resetView()
            keyboardFocused = true
        }
    }

    private func wallpaper(size: CGSize) -> some View {
        ProgressiveCachedAsyncImage(
            lowURL: lowURL,
            highURL: highURL,
            lowMaxPixelDimension: 1600,
            highMaxPixelDimension: 5200
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: mode == .plain ? .fit : .fill)
        } placeholder: {
            // Keep letterboxing neutral in the pure viewer. Reusing the
            // wallpaper's dominant color here reads like an extra UI band.
            Color.black
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .scaleEffect(renderedScale)
        .rotationEffect(.degrees(rotation))
        .offset(
            x: pan.width + (renderedScale > 1 ? liveDrag.width : 0),
            y: pan.height + (renderedScale > 1 ? liveDrag.height : 0)
        )
        .contentShape(Rectangle())
        .gesture(
            MagnificationGesture()
                .updating($liveMagnification) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    scale = min(5, max(0.5, scale * value))
                    if scale <= 1 { pan = .zero }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .updating($liveDrag) { value, state, _ in
                    guard renderedScale > 1 else { return }
                    state = value.translation
                }
                .onEnded { value in
                    guard renderedScale > 1 else {
                        pan = .zero
                        return
                    }
                    pan.width += value.translation.width
                    pan.height += value.translation.height
                }
        )
        .onTapGesture(count: 2) {
            if scale > 1 {
                resetView()
            } else {
                withAnimation(.easeOut(duration: 0.18)) { scale = 2 }
            }
        }
        .animation(.easeOut(duration: 0.18), value: mode)
    }

    private func viewerChrome(size: CGSize) -> some View {
        ZStack {
            VStack {
                modePicker
                    .padding(.top, 18)
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    viewerInfo
                    viewerToolbar
                }
                .padding(.bottom, 22)
            }

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    ViewerToolButton(
                        icon: "xmark",
                        help: L10n.detail.fullscreenClose,
                        size: 42,
                        action: onClose
                    )
                }
                .padding(.top, 18)
                .padding(.trailing, 22)
                Spacer(minLength: 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases, id: \.self) { option in
                let selected = option == mode
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        mode = option
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : Color.black.opacity(0.58))
                        .padding(.horizontal, 22)
                        .frame(height: 38)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.black.opacity(0.92))
                                    .matchedGeometryEffect(id: "fullscreen-preview-mode", in: modeNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(GlassBounceButtonStyle())
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.90)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.65), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 7)
    }

    private var viewerInfo: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(title) · \(metadata)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(Int((renderedScale * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.64))
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.54)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .frame(maxWidth: 620)
    }

    private var viewerToolbar: some View {
        HStack(spacing: 2) {
            ViewerToolButton(icon: "minus.magnifyingglass", help: L10n.detail.fullscreenZoomOut) {
                zoom(by: 1 / 1.25)
            }
            ViewerToolButton(icon: "plus.magnifyingglass", help: L10n.detail.fullscreenZoomIn) {
                zoom(by: 1.25)
            }
            toolbarDivider
            ViewerToolButton(icon: "rotate.right", help: L10n.detail.fullscreenRotate) {
                withAnimation(.easeOut(duration: 0.18)) {
                    rotation = (rotation + 90).truncatingRemainder(dividingBy: 360)
                    pan = .zero
                }
            }
            toolbarDivider
            ViewerToolButton(icon: "arrow.counterclockwise", help: L10n.detail.fullscreenReset) {
                resetView()
            }
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.66)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: 20, y: 8)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.22))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 4)
    }

    private func homeScreenOverlay(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                Text("Wallpaper Exchange")
                    .fontWeight(.semibold)
                Text("File")
                Text("View")
                Spacer(minLength: 0)
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Text(Self.menuBarTime)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(.ultraThinMaterial)

            Spacer(minLength: 0)

            HStack(spacing: 9) {
                dockIcon("face.smiling", tint: Color(red: 0.20, green: 0.64, blue: 0.94))
                dockIcon("safari", tint: Color(red: 0.13, green: 0.54, blue: 0.95))
                dockIcon("envelope.fill", tint: Color(red: 0.18, green: 0.55, blue: 0.94))
                dockIcon("photo.on.rectangle", tint: Color(red: 0.86, green: 0.34, blue: 0.50))
                dockIcon("gearshape.fill", tint: Color(red: 0.45, green: 0.48, blue: 0.52))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.20), radius: 16, y: 7)
            .padding(.bottom, 114)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func dockIcon(_ systemName: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(tint)
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.96))
            }
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.34), lineWidth: 1))
    }

    private func lockScreenOverlay(size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.18), Color.clear, Color.black.opacity(0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 4) {
                    Text(Self.lockDate(context.date))
                        .font(.system(size: 15, weight: .medium))
                    Text(Self.lockTime(context.date))
                        .font(.system(size: min(88, max(52, size.width * 0.065)), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.34), radius: 8, y: 3)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 68)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func zoom(by factor: CGFloat) {
        withAnimation(.easeOut(duration: 0.16)) {
            scale = min(5, max(0.5, scale * factor))
            if scale <= 1 { pan = .zero }
        }
    }

    private func resetView() {
        withAnimation(.easeOut(duration: 0.18)) {
            scale = 1
            rotation = 0
            pan = .zero
        }
    }

    private static var menuBarTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: Date())
    }

    private static func lockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func lockDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.browse.dateLocaleID)
        formatter.dateFormat = L10n.browse.lockDateFormat
        return formatter.string(from: date)
    }
}

private struct ViewerToolButton: View {
    let icon: String
    let help: String
    var size: CGFloat = 44
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(hovering ? 1 : 0.90))
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? Color.white.opacity(0.14) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .onHover { hovering = $0 }
        .help(help)
    }
}
