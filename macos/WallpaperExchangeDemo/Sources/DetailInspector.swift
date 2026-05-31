import SwiftUI

// Right-side inspector that slides in over the grid when a tile is
// clicked. Sized to a 420 px column — wide enough for the hero image
// + action bar + metadata without crowding, narrow enough that the
// grid stays scannable behind it.
//
// Layout (top to bottom):
//   • Header: ✕ close + title + uploader
//   • Hero image with rounded corners + palette strip overlay
//   • Action bar (Plain / Home / Lock toggle + Fullscreen)
//   • Specs (3-col mini grid: Dim / Res / File)
//   • Palette grid (clickable swatches → copy HEX)
//   • Coin CTA (Trade for 1) + Quick action chips
//
// The 'set wallpaper' affordances surface as Quick chips below the
// CTA: per-display targeting for multi-monitor setups.
struct DetailInspector: View {
    let wallpaper: DemoWallpaper
    let onClose: () -> Void

    @State private var mode: PreviewMode = .off
    enum PreviewMode { case off, plain, home, lock }

    var body: some View {
        ZStack {
            // Backdrop: blurred wallpaper preview + a paper-tinted scrim
            // so the inspector content stays readable.
            ZStack {
                AsyncImage(url: wallpaper.previewURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                            .blur(radius: 60)
                            .scaleEffect(1.2)
                    } else {
                        wallpaper.dominant.opacity(0.4)
                    }
                }
                Color.dPaper.opacity(0.78)
            }
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    hero
                    actionBar
                    specs
                    palette
                    coinCTA
                    quickActions
                    similar
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            // Subtle paper border on the leading edge to seam against
            // the grid behind it.
            HStack(spacing: 0) {
                Rectangle().fill(Color.dHair).frame(width: 1)
                Spacer()
            }
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: "\(wallpaper.category) · №\(wallpaper.id)")
                Text(wallpaper.title)
                    .font(.dDisplay18)
                    .foregroundStyle(Color.dInk)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.dPaper2)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Text(String(wallpaper.uploader.prefix(1)).uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.dInk)
                        )
                        .overlay(Circle().stroke(Color.dHair, lineWidth: 0.5))
                    Text("@\(wallpaper.uploader)")
                        .font(.dMono11)
                        .tracking(0.5)
                        .foregroundStyle(Color.dMuted)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dInk2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.dPaper2))
                    .overlay(Circle().stroke(Color.dHair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: wallpaper.previewURL) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    wallpaper.dominant
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.dHair, lineWidth: 1)
            )

            // Mock home/lock overlays — only when the user picks a
            // preview mode below.
            if mode == .home {
                VStack {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.15))
                            .frame(height: 14)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<6) { i in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 22, height: 22)
                                .opacity(Double(i + 1) / 6.0)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12))
                    )
                    .padding(.bottom, 10)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if mode == .lock {
                VStack(spacing: 4) {
                    Spacer().frame(height: 30)
                    Text("9:41")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 6)
                    Text("Sunday · May 31")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // Action bar — Plain / Home / Lock + the bare-wallpaper mode.
    // Each option models the same data shape so a small loop can
    // render them without the tuple-array that confused SourceKit.
    private struct PreviewOption {
        let mode: PreviewMode
        let label: String
        let icon: String
    }
    private static let previewOptions: [PreviewOption] = [
        .init(mode: .off,   label: "Wallpaper", icon: "rectangle.on.rectangle"),
        .init(mode: .plain, label: "Plain",     icon: "macbook"),
        .init(mode: .home,  label: "Home",      icon: "rectangle.grid.2x2"),
        .init(mode: .lock,  label: "Lock",      icon: "clock"),
    ]

    private var actionBar: some View {
        HStack(spacing: 4) {
            ForEach(Self.previewOptions, id: \.label) { opt in
                actionBarItem(opt)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.dPaper2))
        .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
    }

    @ViewBuilder
    private func actionBarItem(_ opt: PreviewOption) -> some View {
        let isOn = mode == opt.mode
        Button(action: { mode = opt.mode }) {
            HStack(spacing: 5) {
                Image(systemName: opt.icon).font(.system(size: 10, weight: .medium))
                Text(opt.label).font(.dSans11)
            }
            .foregroundStyle(isOn ? Color.dInk : Color.dMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn ? Color.dPaper : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var specs: some View {
        HStack(spacing: 0) {
            specCell(label: "DIM", value: "\(wallpaper.width)×\(wallpaper.height)")
            divider
            specCell(label: "RES", value: wallpaper.resolutionLabel)
            divider
            specCell(label: "FILE", value: wallpaper.fileSize)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.dPaper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.dHair, lineWidth: 1)
        )
    }

    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: label)
            Text(value)
                .font(.dMono11)
                .tracking(0.4)
                .foregroundStyle(Color.dInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Color.dHair).frame(width: 1, height: 22)
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "Palette · click to copy")
            HStack(spacing: 6) {
                ForEach(Array(wallpaper.palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(c)
                        .frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dHair, lineWidth: 0.5))
                }
            }
        }
    }

    private var coinCTA: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "Exchange for", tint: Color.dPaper.opacity(0.6))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("1")
                        .font(.dDisplay24)
                        .foregroundStyle(Color.dPaper)
                    Text("coin")
                        .font(.dSans13)
                        .foregroundStyle(Color.dAccent)
                }
                Text("Balance · 124 coins remaining")
                    .font(.dMono10)
                    .tracking(0.6)
                    .foregroundStyle(Color.dPaper.opacity(0.55))
            }
            Spacer()
            Button(action: {}) {
                HStack(spacing: 6) {
                    Circle().fill(Color.white).frame(width: 9, height: 9)
                    Text("Trade")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.dAccent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color.dInk)
        )
    }

    // Quick-action row below the CTA. Multi-monitor case: "Set on
    // main display" + "Set on all". The right-most icon button opens
    // the system Wallpaper settings (skipped for the demo).
    private var quickActions: some View {
        HStack(spacing: 6) {
            quickChip(icon: "rectangle.on.rectangle.angled", label: "Set on main display")
            quickChip(icon: "rectangle.3.group", label: "All")
            Spacer()
            iconChip(icon: "heart")
            iconChip(icon: "tray.and.arrow.down")
            iconChip(icon: "square.and.arrow.up")
        }
    }

    private func quickChip(icon: String, label: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.dSans11)
            }
            .foregroundStyle(Color.dInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.dPaper))
            .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func iconChip(icon: String) -> some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.dInk2)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.dPaper))
                .overlay(Circle().stroke(Color.dHair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var similar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "More like this · 4")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(DemoData.wallpapers.prefix(4)) { wp in
                    AsyncImage(url: wp.previewURL) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            wp.dominant.opacity(0.5)
                        }
                    }
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dHair, lineWidth: 0.5))
                }
            }
        }
    }
}
