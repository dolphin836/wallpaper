import SwiftUI
import AppKit

// Mac take on the web's DeviceFloatingWall. A single scrolling canvas
// where wallpaper tiles are absolutely positioned around a floating
// device mockup. The mockup scroll-follows (stays near the top of the
// viewport), can be dragged to a new cell (snaps on release), and the
// tiles it sweeps over squeeze inward — here the squeeze deforms the
// image itself (non-uniform scale) rather than only compressing height
// like the web.
//
// First pass: combined scroll + scroll-follow + directional squeeze +
// drag-to-cell. Spring/threshold feel is tuned against real runs.
struct DeviceFloatingWall: View {
    let wallpapers: [Wallpaper]
    var onPick: (Wallpaper) -> Void
    var onFeature: (Wallpaper?) -> Void = { _ in }
    var onNearEnd: () -> Void = {}
    /// MD size mode → one extra column (smaller tiles).
    var compact: Bool = false

    @State private var featuredIdx = 0
    @State private var previewX: CGFloat = 0
    @State private var previewY: CGFloat = 0
    @State private var parkedCol = 0
    @State private var parkedRow = 0
    @State private var dragging = false
    @State private var dragOrigin: CGPoint = .zero
    @State private var scrollY: CGFloat = 0

    private let gap: CGFloat = 12
    private let span = 2
    private let followInset: CGFloat = 12

    private struct Dent { var sx: CGFloat = 1; var sy: CGFloat = 1; var anchor: UnitPoint = .center }

    private var deviceAspect: CGFloat {
        guard let s = NSScreen.main ?? NSScreen.screens.first, s.frame.height > 0 else { return 16.0 / 10.0 }
        return s.frame.width / s.frame.height
    }

    private func colCount(_ w: CGFloat) -> Int {
        let base: Int
        if w >= 1400 { base = 4 }
        else if w >= 900 { base = 3 }
        else { base = 2 }
        return compact ? base + 1 : base
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let viewportH = geo.size.height
            let cols = colCount(W)
            let tileW = (W - gap * CGFloat(cols - 1)) / CGFloat(max(1, cols))
            let tileH = min(440, max(150, tileW / max(0.1, deviceAspect)))
            let cellW = tileW + gap
            let cellH = tileH + gap
            let previewW = tileW * CGFloat(span) + gap
            let previewH = tileH * CGFloat(span) + gap

            // Continuous preview rect → discrete cell (70% hysteresis)
            // drives the tile reflow around the mockup footprint.
            let pCol = snapIndex(previewX, cell: cellW, maxIndex: max(0, cols - span))
            let pRow = snapIndex(previewY, cell: cellH, maxIndex: Int.max)
            let layout = positions(count: wallpapers.count, cols: cols, pCol: pCol, pRow: pRow, cellW: cellW, cellH: cellH)
            let wallH = max(previewH, (layout.map { $0.y + tileH }.max() ?? previewH) + 8)
            let maxX = max(0, W - previewW)
            let maxY = max(0, wallH - previewH)

            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    GeometryReader { g in
                        Color.clear.preference(key: WallScrollKey.self,
                                               value: -g.frame(in: .named("devwall")).minY)
                    }
                    .frame(height: 0)

                    ForEach(Array(wallpapers.enumerated()), id: \.element.id) { idx, wp in
                        if idx < layout.count {
                            let p = layout[idx]
                            let d = dent(left: p.x, top: p.y, tileW: tileW, tileH: tileH,
                                         previewW: previewW, previewH: previewH)
                            Button { onPick(wp) } label: {
                                MainGridTile(wallpaper: wp, aspectRatio: deviceAspect)
                            }
                            .buttonStyle(.plain)
                            .frame(width: tileW, height: tileH)
                            .scaleEffect(x: d.sx, y: d.sy, anchor: d.anchor)
                            .offset(x: p.x, y: p.y)
                            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: p.x)
                            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: p.y)
                            .onHover { if $0 { featuredIdx = idx; onFeature(wp) } }
                            .onAppear { if idx >= wallpapers.count - 4 { onNearEnd() } }
                        }
                    }

                    MacBookOutlinePreview(
                        wallpaper: wallpapers.indices.contains(featuredIdx) ? wallpapers[featuredIdx] : wallpapers.first
                    )
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16).fill(Color.paper.opacity(0.6))
                            .shadow(color: .black.opacity(dragging ? 0.20 : 0.10),
                                    radius: dragging ? 22 : 12, y: dragging ? 12 : 6)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.hair, lineWidth: 1))
                    .frame(width: previewW, height: previewH)
                    .scaleEffect(dragging ? 1.02 : 1.0)
                    .offset(x: previewX, y: previewY)
                    .zIndex(10)
                    .gesture(
                        DragGesture(coordinateSpace: .named("devwall"))
                            .onChanged { v in
                                if !dragging { dragging = true; dragOrigin = CGPoint(x: previewX, y: previewY) }
                                previewX = min(maxX, max(0, dragOrigin.x + v.translation.width))
                                previewY = min(maxY, max(0, dragOrigin.y + v.translation.height))
                            }
                            .onEnded { _ in
                                dragging = false
                                parkedCol = snapIndex(previewX, cell: cellW, maxIndex: max(0, cols - span))
                                parkedRow = snapIndex(previewY, cell: cellH, maxIndex: Int.max)
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                    previewX = min(maxX, CGFloat(parkedCol) * cellW)
                                    previewY = min(maxY, max(CGFloat(parkedRow) * cellH, scrollY + followInset))
                                }
                            }
                    )
                    .onHover { hovering in if hovering { NSCursor.openHand.push() } else { NSCursor.pop() } }
                }
                .frame(width: W, height: wallH, alignment: .topLeading)
            }
            .coordinateSpace(name: "devwall")
            .onPreferenceChange(WallScrollKey.self) { v in
                scrollY = v
                if !dragging {
                    // Scroll-follow: keep the mockup ~followInset below the
                    // viewport top, never above its parked row.
                    let baseY = CGFloat(parkedRow) * cellH
                    previewY = min(maxY, max(baseY, v + followInset))
                }
                if v + viewportH > wallH - cellH { onNearEnd() }
            }
            .onChange(of: featuredIdx) { _, _ in
                onFeature(wallpapers.indices.contains(featuredIdx) ? wallpapers[featuredIdx] : nil)
            }
        }
    }

    // 70% hysteresis: only advance to the next cell once past 70% of it.
    private func snapIndex(_ pos: CGFloat, cell: CGFloat, maxIndex: Int) -> Int {
        guard cell > 0 else { return 0 }
        let base = Int(floor(pos / cell))
        let progress = (pos - CGFloat(base) * cell) / cell
        var idx = progress > 0.7 ? base + 1 : base
        idx = max(0, idx)
        if maxIndex != Int.max { idx = min(maxIndex, idx) }
        return idx
    }

    // Row-major tile placement, skipping the 2×2 preview footprint.
    private func positions(count: Int, cols: Int, pCol: Int, pRow: Int, cellW: CGFloat, cellH: CGFloat) -> [CGPoint] {
        guard count > 0, cols > 0 else { return [] }
        var out: [CGPoint] = []
        var r = 0, c = 0
        while out.count < count {
            let inPreview = c >= pCol && c < pCol + span && r >= pRow && r < pRow + span
            if !inPreview { out.append(CGPoint(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH)) }
            c += 1
            if c >= cols { c = 0; r += 1 }
            if r > count + 6 { break }
        }
        return out
    }

    // Directional squeeze: a tile overlapping the (continuously-moving)
    // preview rect scales down on its shorter-overlap axis, anchored to
    // the far edge — so the image visibly deforms toward the mockup.
    private func dent(left: CGFloat, top: CGFloat, tileW: CGFloat, tileH: CGFloat,
                      previewW: CGFloat, previewH: CGFloat) -> Dent {
        let xOv = max(0, min(left + tileW, previewX + previewW) - max(left, previewX))
        let yOv = max(0, min(top + tileH, previewY + previewH) - max(top, previewY))
        if xOv <= 0 || yOv <= 0 { return Dent() }
        let dx = (left + tileW / 2) - (previewX + previewW / 2)
        let dy = (top + tileH / 2) - (previewY + previewH / 2)
        let xRatio = min(1, xOv / tileW)
        let yRatio = min(1, yOv / tileH)
        let dentMax: CGFloat = 0.22
        if xRatio > yRatio {
            return Dent(sx: 1, sy: 1 - min(dentMax, yRatio * 0.7), anchor: dy > 0 ? .bottom : .top)
        } else {
            return Dent(sx: 1 - min(dentMax, xRatio * 0.7), sy: 1, anchor: dx > 0 ? .trailing : .leading)
        }
    }
}

private struct WallScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
