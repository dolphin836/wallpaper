import SwiftUI

// Main Discover content — mirrors the web Discover page:
//   • one unified toolbar: scrollable category chips on the left,
//     a FILTER dropdown + a size (LG/MD) control on the right
//   • a draggable device preview inside the wallpaper wall
//   • tiles that compress and reflow around the device preview
//
// The single FilterMode fully specifies what is fetched and how it is
// sorted (no separate sort toggle), matching the web: Latest, Trending,
// For You (signed-in only), My Device, Live, AI Generated.
struct DiscoverView: View {
    let search: String
    var onPick: (Wallpaper) -> Void
    /// When true (used by the legacy device-match sidebar entry) the
    /// initial filter is forced to .myDevice. Discover itself starts on
    /// Latest.
    var deviceMatch: Bool = false
    /// Set when arriving from a Home "browse more" CTA (e.g. Live / AI).
    var initialFilter: Filter? = nil

    @State private var auth = AuthService.shared
    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var filter: Filter = .latest
    @State private var sizeMode: SizeMode = .lg
    // The wallpaper currently shown on the device mockup. Driven by
    // hovering grid tiles (web "floating wall" feel); falls back to the
    // first feed item.
    @State private var featuredHover: Wallpaper?
    @State private var categories: [Category] = []
    @State private var selectedCategoryID: Int? = nil

    // Category strip overflow tracking — drives the trailing fade that
    // only shows when the chips are wider than the visible strip (so
    // full-screen, where they all fit, gets no fade).
    @State private var chipsContentW: CGFloat = 0
    @State private var chipsViewportW: CGFloat = 0
    private var chipsOverflow: Bool { chipsContentW > chipsViewportW + 1 }
    private var chipsFadeStart: CGFloat {
        guard chipsViewportW > 28 else { return 0.85 }
        return max(0, (chipsViewportW - 28) / chipsViewportW)
    }

    enum Filter: String, CaseIterable, Hashable {
        case latest = "Latest"
        case trending = "Trending"
        case forYou = "For You"
        case myDevice = "My Device"
        case live = "Live"
        case ai = "AI Generated"
    }

    enum SizeMode: String, CaseIterable { case md = "MD", lg = "LG" }

    // For You is only meaningful for signed-in users — hide it for
    // guests so the dropdown doesn't surface an option that immediately
    // falls back to Latest.
    private var availableFilters: [Filter] {
        auth.isLoggedIn
            ? [.latest, .trending, .forYou, .myDevice, .live, .ai]
            : [.latest, .trending, .myDevice, .live, .ai]
    }

    private var gridColumns: [GridItem] {
        switch sizeMode {
        case .lg: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14, alignment: .top)]
        case .md: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12, alignment: .top)]
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                toolbar
                wallFeed
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task(id: "discover-init") {
            if let initialFilter { filter = initialFilter }
            else if deviceMatch { filter = .myDevice }
            if categories.isEmpty {
                if let list = try? await APIClient.shared.fetchCategories() {
                    categories = list.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                }
            }
            await reload()
        }
        .onChange(of: filter) { _, _ in Task { await reload() } }
        .onChange(of: search) { _, _ in Task { await reload() } }
        .onChange(of: selectedCategoryID) { _, _ in Task { await reload() } }
    }

    // ── Feed: the scrolling floating wall + loading / empty / error states.
    // Hovering a tile updates the draggable device preview. ──
    @ViewBuilder
    private var wallFeed: some View {
        if loading && items.isEmpty {
            WallpaperGridSkeleton(
                columns: gridColumns,
                count: sizeMode == .lg ? 12 : 16,
                spacing: sizeMode == .lg ? 14 : 12
            )
        } else if let err = loadError, items.isEmpty {
            errorBanner(err)
        } else if items.isEmpty {
            Text(search.isEmpty ? "No wallpapers." : "No wallpapers match.")
                .font(.sans13).foregroundStyle(Color.muted).padding(.top, 20)
        } else {
            DeviceFloatingWallpaperWall(
                wallpapers: items,
                sizeMode: sizeMode,
                featured: featuredHover ?? items.first,
                onFeature: { featuredHover = $0 },
                onPick: onPick,
                onTileAppear: maybeLoadMore
            )
            feedFooter
        }
    }

    // Infinite-scroll footer — loading spinner, a manual "Load more"
    // fallback, a retry on pagination error, and an end-of-feed marker.
    // Mirrors the web's FeedFooter vocabulary.
    @ViewBuilder
    private var feedFooter: some View {
        Group {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading more…").font(.sans12).foregroundStyle(Color.muted)
                }
            } else if loadError != nil {
                HStack(spacing: 10) {
                    Text("Couldn't load more").font(.sans12).foregroundStyle(Color.ink2)
                    Button("Retry") { Task { await loadMore() } }.controlSize(.small)
                }
            } else if hasMore {
                Button { Task { await loadMore() } } label: {
                    Text("Load more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Color.paper2))
                        .overlay(Capsule().stroke(Color.hair, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("\(items.count) wallpaper\(items.count == 1 ? "" : "s") · You've reached the end")
                    .font(.mono11).tracking(0.5).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // ── Toolbar: chips (left, scrollable) + filter dropdown + size ──
    private var toolbar: some View {
        // One row: [All (pinned)] [scrollable categories] … [filter][size].
        // The category strip is bounded to the available width by the
        // ScrollView, so it can't push the page wider than the window
        // (which was eating the right margin in windowed mode). When the
        // categories all fit (e.g. full-screen), the strip just doesn't
        // scroll. "All" stays pinned at the front, outside the scroll.
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                categoryChip(label: "All", id: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { c in
                            categoryChip(label: c.name, id: c.id)
                        }
                    }
                    .padding(.vertical, 2)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ChipsContentWidthKey.self, value: g.size.width)
                    })
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: ChipsViewportWidthKey.self, value: g.size.width)
                })
                .onPreferenceChange(ChipsContentWidthKey.self) { chipsContentW = $0 }
                .onPreferenceChange(ChipsViewportWidthKey.self) { chipsViewportW = $0 }
                // Trailing fade — only when the chips overflow the strip.
                // The gradient fades the last ~28pt to transparent so the
                // hidden categories read as "scroll for more"; when they
                // all fit it's a flat mask (no fade).
                .mask(
                    LinearGradient(
                        stops: chipsOverflow
                            ? [.init(color: .black, location: 0),
                               .init(color: .black, location: chipsFadeStart),
                               .init(color: .clear, location: 1)]
                            : [.init(color: .black, location: 0),
                               .init(color: .black, location: 1)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            filterMenu
            sizeControl
        }
        // Sit above the device banner / feed so nothing layered below can
        // intercept the chip taps.
        .zIndex(1)
    }

    private func categoryChip(label: String, id: Int?) -> some View {
        let active = selectedCategoryID == id
        return Button { selectedCategoryID = id } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.paper : Color.ink2)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(active ? Color.ink : Color.paper))
                .overlay(Capsule().stroke(active ? Color.ink : Color.hair, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // FILTER dropdown — matches the web's labelled dropdown.
    private var filterMenu: some View {
        Menu {
            ForEach(availableFilters, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    if filter == f {
                        Label(f.rawValue, systemImage: "checkmark")
                    } else {
                        Text(f.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("FILTER")
                    .font(.mono10).tracking(1.2).foregroundStyle(Color.muted)
                Text(filter.rawValue)
                    .font(.sans12).foregroundStyle(Color.ink2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.paper2))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hair, lineWidth: 1))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    // LG / MD size segmented control — matches the web's SizeControls.
    private var sizeControl: some View {
        HStack(spacing: 2) {
            ForEach([SizeMode.md, .lg], id: \.self) { s in
                let on = sizeMode == s
                Button(action: { sizeMode = s }) {
                    Text(s.rawValue)
                        .font(.system(size: 11, weight: on ? .semibold : .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(on ? Color.paper : Color.muted)
                        .frame(minWidth: 30, minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? Color.ink : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.paper2))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hair, lineWidth: 1))
        .fixedSize()
    }

    private func errorBanner(_ msg: String) -> some View {
        RemoteLoadErrorView(message: msg) {
            Task { await reload() }
        }
    }

    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false; loadError = nil; featuredHover = nil
        if filter == .forYou {
            await loadForYou()
        } else {
            await loadMore()
        }
    }

    // For You is a single-shot top-N feed. On empty (cold-start users)
    // fall back to Latest so the page still shows content — the filter
    // change re-triggers reload via onChange.
    private func loadForYou() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let list = try await APIClient.shared.fetchForYou(limit: 30)
            if list.isEmpty {
                filter = .latest
                return
            }
            items = list
            cursor = nil
            hasMore = false
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await APIClient.shared.fetchWallpapers(
                cursor: cursor,
                limit: 24,
                dynamicOnly: filter == .live,
                aiOnly: filter == .ai,
                search: search.isEmpty ? nil : search,
                categoryID: selectedCategoryID,
                sort: filter == .trending ? "trending" : nil,
                deviceMatch: filter == .myDevice,
                // Live = Mac dynamic ∪ video (dynamic_only spans both
                // server-side); opt video back in for this filter.
                includeVideo: filter == .live
            )
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct DeviceFloatingWallpaperWall: View {
    let wallpapers: [Wallpaper]
    let sizeMode: DiscoverView.SizeMode
    let featured: Wallpaper?
    var onFeature: (Wallpaper) -> Void
    var onPick: (Wallpaper) -> Void
    var onTileAppear: (Wallpaper) -> Void

    @State private var wallWidth: CGFloat = 0
    @State private var previewOffset: CGPoint = .zero
    @State private var previewCell = DeviceWallCell()
    @State private var parkedCell = DeviceWallCell()
    @State private var dragStartOffset: CGPoint = .zero
    @State private var dragging = false
    @State private var measuredHeight: CGFloat = 420

    private let gap: CGFloat = 12
    private let previewSpan = 2
    private let snapThreshold: CGFloat = 0.70
    private var measuringHeight: CGFloat { sizeMode == .lg ? 420 : 300 }
    private var fallbackWallWidth: CGFloat {
        max(640, (NSScreen.main?.visibleFrame.width ?? 1280) - 360)
    }

    private var deviceAspect: CGFloat {
        let req = MacScreenRequirement.current
        guard req.height > 0 else { return 16.0 / 10.0 }
        return CGFloat(req.width) / CGFloat(req.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width > 1 ? proxy.size.width : fallbackWallWidth
            let layout = makeLayout(width: width, previewCell: previewCell)
            let height = layout.isReady ? max(layout.wallHeight, layout.previewH) : measuringHeight

            wallContent(layout: layout)
                .frame(width: width, height: height, alignment: .topLeading)
                .onAppear {
                    syncGeometry(width: width, height: height, layout: layout)
                }
                .onChange(of: proxy.size.width) { _, _ in
                    syncGeometry(width: width, height: height, layout: layout)
                }
                .onChange(of: wallpapers.count) { _, _ in
                    syncGeometry(width: width, height: height, layout: layout)
                }
        }
        .frame(height: measuredHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: sizeMode) { _, _ in
            previewCell = .zero
            parkedCell = .zero
            measuredHeight = measuringHeight
            settleToParkedCell(animated: false)
        }
    }

    private func wallContent(layout: DeviceWallLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.positions) { pos in
                let wp = wallpapers[pos.index]
                let squeeze = squeeze(for: pos.frame, layout: layout)
                Button(action: { onPick(wp) }) {
                    MainGridTile(wallpaper: wp, aspectRatio: deviceAspect)
                }
                .buttonStyle(.plain)
                .frame(width: pos.frame.width, height: pos.frame.height)
                .scaleEffect(x: squeeze.x, y: squeeze.y, anchor: squeeze.anchor)
                .offset(x: pos.frame.minX, y: pos.frame.minY)
                .zIndex(1)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: previewCell)
                .onHover { hovering in
                    if hovering { onFeature(wp) }
                }
                .onAppear { onTileAppear(wp) }
            }

            if let featured, layout.isReady {
                DeviceMockup(
                    wallpaper: featured,
                    maxMonitorWidth: layout.mockupMaxWidth,
                    chromePadding: layout.chromePadding,
                    chromeSpacing: layout.chromeSpacing
                )
                .frame(width: layout.previewW, height: layout.previewH)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .offset(x: previewOffset.x, y: previewOffset.y)
                .zIndex(5)
                .shadow(color: .black.opacity(dragging ? 0.18 : 0.10), radius: dragging ? 26 : 18, y: dragging ? 12 : 8)
                .scaleEffect(dragging ? 1.012 : 1)
                .gesture(dragGesture(layout: layout))
                .animation(.easeOut(duration: 0.16), value: dragging)
            }
        }
    }

    private func syncGeometry(width: CGFloat, height: CGFloat, layout: DeviceWallLayout) {
        guard layout.isReady else { return }
        if abs(wallWidth - width) > 0.5 {
            wallWidth = width
        }
        if abs(measuredHeight - height) > 0.5 {
            measuredHeight = height
        }
        let nextParked = clampCell(parkedCell, layout: layout)
        if parkedCell != nextParked {
            parkedCell = nextParked
        }
        let nextPreviewCell = clampCell(previewCell, layout: layout)
        if previewCell != nextPreviewCell {
            previewCell = nextPreviewCell
        }
        let nextOffset = clampOffset(previewOffset, layout: layout)
        if abs(previewOffset.x - nextOffset.x) > 0.5 || abs(previewOffset.y - nextOffset.y) > 0.5 {
            previewOffset = nextOffset
        }
    }

    private func dragGesture(layout: DeviceWallLayout) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    dragStartOffset = previewOffset
                }
                let proposed = CGPoint(
                    x: dragStartOffset.x + value.translation.width,
                    y: dragStartOffset.y + value.translation.height
                )
                let clamped = clampOffset(proposed, layout: layout)
                previewOffset = clamped
                previewCell = cell(for: clamped, layout: layout)
            }
            .onEnded { _ in
                let layout = makeLayout(width: wallWidth, previewCell: previewCell)
                dragging = false
                parkedCell = previewCell
                let target = origin(for: parkedCell, layout: layout)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    previewOffset = clampOffset(target, layout: layout)
                }
            }
    }

    private func settleToParkedCell(animated: Bool) {
        let layout = makeLayout(width: wallWidth, previewCell: previewCell)
        guard layout.isReady else { return }
        let clampedCell = clampCell(parkedCell, layout: layout)
        parkedCell = clampedCell
        previewCell = clampCell(previewCell, layout: layout)
        let target = clampOffset(origin(for: clampedCell, layout: layout), layout: layout)
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { previewOffset = target }
        } else {
            previewOffset = target
        }
    }

    private func makeLayout(width: CGFloat, previewCell: DeviceWallCell) -> DeviceWallLayout {
        let cols = columns(for: width)
        guard width > 1, cols >= previewSpan else {
            return DeviceWallLayout(cols: previewSpan, gap: gap, tileW: 0, tileH: 0, previewW: 0, previewH: 0, wallHeight: 0, positions: [])
        }

        let tileW = (width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let rawTileH = tileW / max(deviceAspect, 0.1)
        let tileH = min(480, max(140, rawTileH))
        let previewW = tileW * CGFloat(previewSpan) + gap * CGFloat(previewSpan - 1)
        let previewH = tileH * CGFloat(previewSpan) + gap * CGFloat(previewSpan - 1)
        let cell = clampCell(previewCell, cols: cols)
        let positions = positionsForTiles(count: wallpapers.count, cols: cols, tileW: tileW, tileH: tileH, previewCell: cell)
        let maxBottom = positions.reduce(previewH) { partial, pos in
            max(partial, pos.frame.maxY)
        }
        return DeviceWallLayout(
            cols: cols,
            gap: gap,
            tileW: tileW,
            tileH: tileH,
            previewW: previewW,
            previewH: previewH,
            wallHeight: maxBottom,
            positions: positions
        )
    }

    private func columns(for width: CGFloat) -> Int {
        switch sizeMode {
        case .lg:
            return width >= 1180 ? 3 : 2
        case .md:
            if width >= 1420 { return 5 }
            if width >= 1060 { return 4 }
            if width >= 760 { return 3 }
            return 2
        }
    }

    private func positionsForTiles(count: Int, cols: Int, tileW: CGFloat, tileH: CGFloat, previewCell: DeviceWallCell) -> [DeviceWallPosition] {
        guard count > 0 else { return [] }
        let cellW = tileW + gap
        let cellH = tileH + gap
        let previewEndCol = previewCell.col + previewSpan
        let previewEndRow = previewCell.row + previewSpan
        var positions: [DeviceWallPosition] = []
        var row = 0
        var col = 0

        while positions.count < count {
            let insidePreview = col >= previewCell.col && col < previewEndCol && row >= previewCell.row && row < previewEndRow
            if !insidePreview {
                let frame = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH, width: tileW, height: tileH)
                positions.append(DeviceWallPosition(index: positions.count, frame: frame))
            }
            col += 1
            if col >= cols {
                col = 0
                row += 1
            }
        }
        return positions
    }

    private func cell(for offset: CGPoint, layout: DeviceWallLayout) -> DeviceWallCell {
        guard layout.isReady else { return .zero }
        let rawCol = offset.x / layout.cellW
        let rawRow = offset.y / layout.cellH
        let baseCol = max(0, Int(floor(rawCol)))
        let baseRow = max(0, Int(floor(rawRow)))
        let colProgress = rawCol - CGFloat(baseCol)
        let rowProgress = rawRow - CGFloat(baseRow)
        return clampCell(
            DeviceWallCell(
                col: colProgress > snapThreshold ? baseCol + 1 : baseCol,
                row: rowProgress > snapThreshold ? baseRow + 1 : baseRow
            ),
            layout: layout
        )
    }

    private func clampCell(_ cell: DeviceWallCell, layout: DeviceWallLayout) -> DeviceWallCell {
        clampCell(cell, cols: layout.cols)
    }

    private func clampCell(_ cell: DeviceWallCell, cols: Int) -> DeviceWallCell {
        let maxCol = max(0, cols - previewSpan)
        return DeviceWallCell(col: min(max(cell.col, 0), maxCol), row: max(cell.row, 0))
    }

    private func origin(for cell: DeviceWallCell, layout: DeviceWallLayout) -> CGPoint {
        CGPoint(x: CGFloat(cell.col) * layout.cellW, y: CGFloat(cell.row) * layout.cellH)
    }

    private func clampOffset(_ offset: CGPoint, layout: DeviceWallLayout) -> CGPoint {
        CGPoint(
            x: min(max(0, offset.x), layout.maxPreviewX),
            y: min(max(0, offset.y), layout.maxPreviewY)
        )
    }

    private func squeeze(for frame: CGRect, layout: DeviceWallLayout) -> DeviceWallSqueeze {
        guard layout.isReady else { return .identity }
        let previewFrame = CGRect(origin: previewOffset, size: CGSize(width: layout.previewW, height: layout.previewH))
        let overlapX = max(0, min(frame.maxX, previewFrame.maxX) - max(frame.minX, previewFrame.minX))
        let overlapY = max(0, min(frame.maxY, previewFrame.maxY) - max(frame.minY, previewFrame.minY))
        guard overlapX > 0, overlapY > 0 else { return .identity }

        let dx = frame.midX - previewFrame.midX
        let dy = frame.midY - previewFrame.midY
        let xRatio = min(1, overlapX / max(frame.width, 1))
        let yRatio = min(1, overlapY / max(frame.height, 1))
        let maxDent: CGFloat = 0.20

        if xRatio > yRatio {
            let scaleY = 1 - min(maxDent, yRatio * 0.70)
            return DeviceWallSqueeze(x: 1, y: scaleY, anchor: dy > 0 ? .bottom : .top)
        } else {
            let scaleX = 1 - min(maxDent, xRatio * 0.70)
            return DeviceWallSqueeze(x: scaleX, y: 1, anchor: dx > 0 ? .trailing : .leading)
        }
    }
}

private struct DeviceWallLayout {
    let cols: Int
    let gap: CGFloat
    let tileW: CGFloat
    let tileH: CGFloat
    let previewW: CGFloat
    let previewH: CGFloat
    let wallHeight: CGFloat
    let positions: [DeviceWallPosition]

    var isReady: Bool { tileW > 0 && tileH > 0 && previewW > 0 && previewH > 0 }
    var cellW: CGFloat { tileW + gap }
    var cellH: CGFloat { tileH + gap }
    var maxPreviewX: CGFloat { max(0, CGFloat(cols) * cellW - gap - previewW) }
    var maxPreviewY: CGFloat { max(0, wallHeight - previewH) }
    var mockupMaxWidth: CGFloat { max(180, min(520, previewW - 44)) }
    var chromePadding: CGFloat { previewH < 360 ? 18 : 28 }
    var chromeSpacing: CGFloat { previewH < 360 ? 10 : 18 }
}

private struct DeviceWallPosition: Identifiable {
    let index: Int
    let frame: CGRect
    var id: Int { index }
}

private struct DeviceWallCell: Equatable {
    var col: Int = 0
    var row: Int = 0
    static let zero = DeviceWallCell()
}

private struct DeviceWallSqueeze {
    var x: CGFloat
    var y: CGFloat
    var anchor: UnitPoint
    static let identity = DeviceWallSqueeze(x: 1, y: 1, anchor: .center)
}

// Width probes for the category strip: the inner HStack reports its
// intrinsic content width, the ScrollView its visible width. When the
// former exceeds the latter the strip overflows and the trailing fade
// turns on.
private struct ChipsContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct ChipsViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
