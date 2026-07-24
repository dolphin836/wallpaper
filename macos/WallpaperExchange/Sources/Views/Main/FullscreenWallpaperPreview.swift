import SwiftUI

// Full-window image viewer used by DetailPage. It mirrors the web viewer's
// image-first layout and zoom / rotate / reset controls.
struct FullscreenWallpaperPreview: View {
    let lowURL: URL?
    let highURL: URL?
    let resolutionName: String
    let dimensions: String
    let onClose: () -> Void
    @State private var scale: CGFloat = 1
    @State private var rotation = 0.0
    @State private var pan: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveDrag: CGSize = .zero
    @FocusState private var keyboardFocused: Bool

    private var renderedScale: CGFloat {
        min(5, max(0.5, scale * liveMagnification))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                wallpaper(size: proxy.size)

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
                .aspectRatio(contentMode: .fit)
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
    }

    private func viewerChrome(size: CGSize) -> some View {
        ZStack {
            VStack {
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

    private var viewerInfo: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Generic \(resolutionName) · \(dimensions)")
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
