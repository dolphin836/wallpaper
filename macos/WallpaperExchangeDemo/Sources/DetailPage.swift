import SwiftUI

// Full-page wallpaper detail. Pushed onto the navigation stack from
// the Discover grid (or any wallpaper tile). Layout mirrors the web
// Spotlight design adapted for the wider desktop column:
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │ Back · breadcrumb                              ✕ Close (esc) │
//   ├──────────────────────────────────────────────────────────────┤
//   │                                                              │
//   │              ┌─────────────────────────────┐                 │
//   │              │       HERO (clickable       │                 │
//   │              │  to fullscreen + Plain/     │                 │
//   │              │  Home/Lock overlay)         │                 │
//   │              └─────────────────────────────┘                 │
//   │  3024×1964 · 4K · JPG · 2.3 MB · DYNAMIC                     │
//   │  ─────────────────────────────────────────────────────       │
//   │  [♥] [☆] [+ List]   [Plain Home Lock ⛶]   [Devices · 12]    │
//   │                                              [Trade for 1]   │
//   ├──────────────────────────────────────────────────────────────┤
//   │ Stats strip   ·  Uploader · About · Palette                  │
//   ├──────────────────────────────────────────────────────────────┤
//   │ More like this · grid                                        │
//   └──────────────────────────────────────────────────────────────┘
//
// The page leaves the toolbar back chrome to NavigationStack's
// default macOS rendering and adds an editorial close button on the
// right for ESC parity with the web.
struct DetailPage: View {
    let wallpaper: DemoWallpaper
    var onUploader: (String) -> Void = { _ in }
    var onCollection: (Int, String) -> Void = { _, _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var mode: PreviewMode = .off
    enum PreviewMode: String { case off = "Wallpaper", plain = "Plain", home = "Home", lock = "Lock" }

    var body: some View {
        ZStack {
            backdrop
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    breadcrumb
                    hero
                    actionBar
                    metaGrid
                    moreLikeThis
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 48)
                .padding(.top, 12)
                .padding(.bottom, 60)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationBarBackButtonHidden(false)
    }

    private var backdrop: some View {
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
    }

    private var breadcrumb: some View {
        HStack(alignment: .center, spacing: 10) {
            Kicker(text: "Specimen №\(wallpaper.id)")
            Spacer()
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                    Text("ESC").font(.dKicker).tracking(1.5)
                }
                .foregroundStyle(Color.dInk2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.dPaper2))
                .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    // Hero card. Wider than the inspector version (max-w 880 px so it
    // breathes on big windows but doesn't sprawl on a 5K display).
    private var hero: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: wallpaper.previewURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        wallpaper.dominant
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 440)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18).stroke(Color.dHair, lineWidth: 1)
                )

                if mode == .home { HomeMockOverlay() }
                if mode == .lock { LockMockOverlay() }
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity, alignment: .center)

            // Title under hero — left-aligned, full-width up to the
            // hero's container width, so the page reads like an
            // editorial spread.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wallpaper.title)
                        .font(.dDisplay24)
                        .foregroundStyle(Color.dInk)
                    HStack(spacing: 8) {
                        Text("\(wallpaper.width)×\(wallpaper.height) px")
                        Text("·")
                        Text(wallpaper.resolutionLabel)
                        Text("·")
                        Text(wallpaper.fileSize)
                        if wallpaper.isDynamic {
                            Text("·").padding(.leading, 2)
                            Text("DYNAMIC").foregroundStyle(Color.dAccent)
                        }
                    }
                    .font(.dMono11)
                    .tracking(0.5)
                    .foregroundStyle(Color.dMuted)
                }
                Spacer()
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private struct PreviewOption {
        let mode: PreviewMode
        let icon: String
    }
    private static let previewOptions: [PreviewOption] = [
        .init(mode: .off,   icon: "rectangle.on.rectangle"),
        .init(mode: .plain, icon: "macbook"),
        .init(mode: .home,  icon: "rectangle.grid.2x2"),
        .init(mode: .lock,  icon: "clock"),
    ]

    // Action bar — three groups separated by dividers. Social on the
    // left, preview toggle in the middle, Get + Trade on the right.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Group {
                actionPill(icon: "heart", label: "Like", count: "\(wallpaper.likes)")
                actionPill(icon: "star", label: "Favorite", count: nil)
                actionPill(icon: "rectangle.stack.badge.plus", label: "Add to list", count: nil)
            }
            divider
            HStack(spacing: 4) {
                ForEach(Self.previewOptions, id: \.mode.rawValue) { opt in
                    Button(action: { mode = opt.mode }) {
                        HStack(spacing: 5) {
                            Image(systemName: opt.icon).font(.system(size: 10, weight: .medium))
                            Text(opt.mode.rawValue).font(.dSans11)
                        }
                        .foregroundStyle(mode == opt.mode ? Color.dInk : Color.dMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(mode == opt.mode ? Color.dPaper : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.dPaper2))
            .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
            divider
            actionPill(icon: "laptopcomputer", label: "Devices", count: "12")
            // Coin CTA pill — accent-on-ink, the only saturated colour on
            // the action bar so it pulls focus.
            Button(action: {}) {
                HStack(spacing: 7) {
                    Circle().fill(Color.dAccent).frame(width: 9, height: 9)
                    Text("Trade for 1")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dPaper)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.dInk))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color.dPaper.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color.dHair, lineWidth: 1)
        )
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func actionPill(icon: String, label: String, count: String?) -> some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.dSans11)
                if let c = count {
                    Text(c)
                        .font(.dMono10)
                        .tracking(0.4)
                        .foregroundStyle(Color.dMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.dPaper2))
                }
            }
            .foregroundStyle(Color.dInk2)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.dPaper))
            .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Color.dHair).frame(width: 1, height: 22)
    }

    // 3-column metadata strip — Uploader / About / Palette. Same axes
    // as the web's content card. Each section is its own card with the
    // paper background to give the page rhythm.
    private var metaGrid: some View {
        VStack(spacing: 0) {
            statsStrip
            HStack(alignment: .top, spacing: 24) {
                uploaderCell
                aboutCell
                paletteCell
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.dPaper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.dHair, lineWidth: 1)
        )
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statCell(label: "DOWNLOADS", value: "\(wallpaper.downloads)")
            divider
            statCell(label: "LIKES", value: "\(wallpaper.likes)")
            divider
            statCell(label: "FAVORITED", value: "24")
            divider
            statCell(label: "VIEWS", value: "1,240")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dHair).frame(height: 1)
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: label)
            Text(value).font(.dDisplay18).foregroundStyle(Color.dInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var uploaderCell: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: "Uploaded by")
            Button(action: { onUploader(wallpaper.uploader) }) {
                HStack(spacing: 10) {
                    Circle().fill(Color.dPaper2).frame(width: 40, height: 40)
                        .overlay(Text(String(wallpaper.uploader.prefix(1)).uppercased()).font(.dDisplay18).foregroundStyle(Color.dInk))
                        .overlay(Circle().stroke(Color.dHair, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(wallpaper.uploader)").font(.dSans13).foregroundStyle(Color.dInk)
                        Text("VIEW PROFILE →").font(.dKicker).tracking(2).foregroundStyle(Color.dMuted)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aboutCell: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: "About")
            Text(wallpaper.category)
                .font(.dDisplay18)
                .foregroundStyle(Color.dInk)
            // Tag chips tinted with the palette in rotation, mirroring
            // the web's About column.
            FlowChips(tags: wallpaper.tags, palette: wallpaper.palette)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paletteCell: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: "Palette · \(wallpaper.palette.count) colors")
            HStack(spacing: 4) {
                ForEach(Array(wallpaper.palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(c)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dHair, lineWidth: 0.5))
                }
            }
            HStack(spacing: 6) {
                Rectangle().fill(wallpaper.dominant).frame(width: 12, height: 12).cornerRadius(2)
                Text("DOMINANT").font(.dKicker).tracking(2).foregroundStyle(Color.dMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreLikeThis: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("More like this · \(DemoData.wallpapers.count - 1)")
                    .font(.dDisplay18)
                    .foregroundStyle(Color.dInk)
                Spacer()
                Rectangle().fill(Color.dHair).frame(height: 1)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)],
                spacing: 14
            ) {
                ForEach(DemoData.wallpapers.filter { $0.id != wallpaper.id }) { wp in
                    NavigationLink(value: MainWindow.Route.detail(wp)) {
                        WallpaperTile(wallpaper: wp)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// Wrap-onto-multiple-lines tag chips. Each chip tints itself from the
// palette in rotation.
struct FlowChips: View {
    let tags: [String]
    let palette: [Color]
    var body: some View {
        // Quick + dirty flow layout via wrapped HStacks. For demo, the
        // tag count is small enough that a single HStack with wrap
        // behavior covers the common case.
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { i, tag in
                let c = palette[i % max(1, palette.count)]
                HStack(spacing: 4) {
                    Circle().fill(c).frame(width: 6, height: 6)
                    Text(tag).font(.dSans11)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(c.blend(with: Color.dInk, fraction: 0.4))
                .background(
                    Capsule().fill(c.opacity(0.12))
                )
                .overlay(Capsule().stroke(c, lineWidth: 1))
            }
        }
    }
}

extension Color {
    // Lightweight RGB blend so chip text leans toward ink while still
    // being palette-tinted.
    func blend(with other: Color, fraction: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let r = a.redComponent   * (1 - fraction) + b.redComponent   * fraction
        let g = a.greenComponent * (1 - fraction) + b.greenComponent * fraction
        let bl = a.blueComponent * (1 - fraction) + b.blueComponent  * fraction
        return Color(red: r, green: g, blue: bl)
    }
}

// Minimal flow layout (macOS 14 ships SwiftUI's Layout protocol so
// we can implement it natively — no UIKit fallback).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                widest = max(widest, x - spacing)
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: widest, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            _ = maxW
        }
    }
}

// Mock home / lock overlays painted over the hero in the matching
// preview mode. Same visual language as the web's dev-overlay-* CSS.
struct HomeMockOverlay: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 22)
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(0..<6) { i in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .opacity(Double(i + 1) / 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.12)))
            .padding(.bottom, 18)
        }
    }
}

struct LockMockOverlay: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 80)
            Text("9:41")
                .font(.system(size: 86, weight: .ultraLight))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 12)
            Text("Sunday · May 31")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
