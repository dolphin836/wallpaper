import AppKit
import SwiftUI

// Weekly Picks archive — the "magazine rack".
//
// No timeline pane: the latest issue opens the page as a full-width
// spread (21:9 cover + a wrapping grid of the rest of its slate, lazily
// fetched), and every past issue sits below as a cover card in a
// full-width adaptive grid. Covers open the week page; strip thumbs
// open the wallpaper detail directly.
struct WeeklyArchiveView: View {
    var onOpenWeek: (Int, Int) -> Void
    var onPick: WallpaperSelectionHandler = { _, _ in }

    @State private var entries: [WeeklyArchiveEntry] = []
    @State private var loading = false
    @State private var loadError: String?
    // Latest issue's slate for the spread strip.
    @State private var latestPicks: [WeeklyPicked] = []
    @State private var loadingPicks = false

    private var latest: WeeklyArchiveEntry? { entries.first }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - 80)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if loading && entries.isEmpty {
                        archiveSkeleton(availableWidth: contentWidth).padding(.top, 32)
                    } else if let err = loadError, entries.isEmpty {
                        RemoteLoadErrorView(message: err) {
                            Task { await load() }
                        }
                    } else if entries.isEmpty {
                        RemoteEmptyStateView(
                            title: L10n.home.archiveEmptyTitle,
                            message: L10n.home.archiveEmptyMessage,
                            symbol: "calendar"
                        )
                    } else {
                        if let latest {
                            latestSpread(latest, availableWidth: contentWidth).padding(.top, 32)
                        }
                        if entries.count > 1 {
                            pastIssuesSection.padding(.top, 56)
                        }
                    }
                }
                .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .task { await load() }
        .task(id: latest?.id) { await loadLatestPicks() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private func archiveSkeleton(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonPlate(aspectRatio: 21.0 / 9.0, cornerRadius: 18)
            stripSkeleton(availableWidth: availableWidth)
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 16) {
                SkeletonLine(width: 112, height: 9)
                LazyVGrid(columns: pastCols, spacing: 28) {
                    ForEach(0..<pastSkeletonCount(for: availableWidth), id: \.self) { _ in
                        SkeletonPlate(aspectRatio: 16.0 / 10.0, cornerRadius: 18)
                    }
                }
            }
            .padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: L10n.home.archiveKicker)
            Text(L10n.home.archiveTitle)
                .font(.display32).foregroundStyle(Color.ink)
            Text(L10n.home.archiveIntro)
                .font(.sans13).foregroundStyle(Color.ink2)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    // ─── Latest issue spread ─────────────────────────────────────

    private func latestSpread(_ s: WeeklyArchiveEntry, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { onOpenWeek(s.year, s.week) } label: {
                latestCover(s)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            latestStrip(s, availableWidth: availableWidth)
        }
    }

    private func latestCover(_ s: WeeklyArchiveEntry) -> some View {
        // Color.clear sets a strict 21:9 box; the cover fills it as an
        // overlay and is clipped, so a large image can't overflow.
        Color.clear
            .aspectRatio(21.0 / 9.0, contentMode: .fit)
            .overlay {
                ProgressiveCachedAsyncImage(
                    lowURL: cleanURL(s.coverURL),
                    highURL: cleanURL(s.originalURL),
                    lowMaxPixelDimension: 1400,
                    highMaxPixelDimension: 4200
                ) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: s.dominantColor ?? "#bbb").opacity(0.5)
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.58)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.home.issueLabel).font(.kicker).tracking(2.4).foregroundStyle(.white.opacity(0.85))
                    Text(L10n.home.weekTitle(s.week))
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    Text("\(Self.fmtDate(s.year, s.week)) \(String(s.year)) · \(L10n.home.picksCountCaps(s.count))")
                        .font(.mono11).tracking(0.6).foregroundStyle(.white.opacity(0.85))
                }
                .padding(24)
            }
            .overlay(alignment: .bottomTrailing) {
                GlassCapsuleButton(title: L10n.home.viewAllPicks(s.count), icon: "arrow.right", style: .paper, height: 32, fontSize: 12) {
                    onOpenWeek(s.year, s.week)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.20), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
            .id(s.id)
    }

    // The rest of the latest slate as a wrapping grid of square thumbs —
    // a quick taste of the issue without leaving the page. Fixed-size cells
    // preserve the compact strip rhythm while keeping every item inside the
    // page's content width.
    @ViewBuilder
    private func latestStrip(_ s: WeeklyArchiveEntry, availableWidth: CGFloat) -> some View {
        let hero = latestPicks.first(where: { $0.isHero }) ?? latestPicks.first
        let rest = latestPicks.filter { $0.id != hero?.id }
        if loadingPicks && latestPicks.isEmpty {
            stripSkeleton(availableWidth: availableWidth)
        } else if !rest.isEmpty {
            LazyVGrid(columns: stripCols, alignment: .leading, spacing: 8) {
                ForEach(rest) { p in
                    stripThumb(p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stripThumb(_ p: WeeklyPicked) -> some View {
        Button(action: { onPick(p.asWallpaper(), latestPicks.map { $0.asWallpaper() }) }) {
            CachedAsyncImage(url: cleanURL(p.thumbURL), maxPixelDimension: 400) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(hex: p.dominantColor ?? "#bbb").opacity(0.5)
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(GlassBounceButtonStyle())
        .pointerCursor()
        .onHover { h in
            if h { PaletteEnv.shared.apply(palette: p.colorPalette, dominant: p.dominantColor) }
            else { PaletteEnv.shared.resetToDefaults() }
        }
    }

    // ─── Past issues rack ────────────────────────────────────────

    private var pastIssuesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Kicker(text: L10n.home.archiveKicker)
            LazyVGrid(columns: pastCols, spacing: 28) {
                ForEach(Array(entries.dropFirst())) { e in
                    Button { onOpenWeek(e.year, e.week) } label: {
                        WeeklyIssueCard(entry: e, dateText: Self.fmtDate(e.year, e.week))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Full-width adaptive grid — no maximum, columns stretch to the
    // page gutters (3-up windowed, 4-up full-screen).
    private var pastCols: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 28, alignment: .top)]
    }

    private var stripCols: [GridItem] {
        [GridItem(.adaptive(minimum: 108, maximum: 108), spacing: 8, alignment: .top)]
    }

    private func stripSkeleton(availableWidth: CGFloat) -> some View {
        LazyVGrid(columns: stripCols, alignment: .leading, spacing: 8) {
            ForEach(0..<stripSkeletonCount(for: availableWidth), id: \.self) { _ in
                SkeletonPlate(aspectRatio: 1, cornerRadius: 10, shadow: false)
                    .frame(width: 108, height: 108)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stripSkeletonCount(for availableWidth: CGFloat) -> Int {
        max(1, Int(floor((availableWidth + 8) / (108 + 8))))
    }

    private func pastSkeletonCount(for availableWidth: CGFloat) -> Int {
        let columns = max(1, Int(floor((availableWidth + 28) / (300 + 28))))
        return columns * 2
    }

    private func load() async {
        loadError = nil
        loading = true; defer { loading = false }
        do {
            entries = try await APIClient.shared.fetchWeeklyArchive(limit: 100)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadLatestPicks() async {
        guard let s = latest, latestPicks.isEmpty else { return }
        loadingPicks = true
        defer { loadingPicks = false }
        if let data = try? await APIClient.shared.fetchWeeklyByWeek(year: s.year, week: s.week) {
            latestPicks = data.picks
        }
    }

    private func cleanURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    // ISO-week → that week's Friday (weeklies drop Fridays), UTC. → "JUN 05".
    static func fmtDate(_ year: Int, _ week: Int) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.weekOfYear = week
        comps.yearForWeekOfYear = year
        comps.weekday = 6 // Friday
        let date = cal.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMM dd"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: date).uppercased()
    }
}

// A past issue on the rack — 16:10 cover card with the issue stamp on
// a bottom scrim. Hover lifts the card and tints the page mesh.
private struct WeeklyIssueCard: View {
    let entry: WeeklyArchiveEntry
    let dateText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay {
                CachedAsyncImage(url: URL(string: entry.coverURL), maxPixelDimension: 1100) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: entry.dominantColor ?? "#bbb").opacity(0.5)
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.home.weekTitle(entry.week))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    Text("\(dateText) \(String(entry.year)) · \(L10n.home.picksCountCaps(entry.count))")
                        .font(.mono10).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(hover ? 0.55 : 0.35), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.20), radius: 3, y: 2)
            .shadow(color: .black.opacity(hover ? 0.34 : 0.22), radius: hover ? 22 : 14, y: hover ? 12 : 7)
            .scaleEffect(reduceMotion ? 1 : (hover ? 1.015 : 1))
            .animation(.easeOut(duration: 0.18), value: hover)
            .onHover { h in
                hover = h
                if h { PaletteEnv.shared.apply(palette: entry.colorPalette, dominant: entry.dominantColor) }
                else { PaletteEnv.shared.resetToDefaults() }
            }
            .contentShape(Rectangle())
    }
}


extension WeeklyPicked {
    // WeeklyPicked → Wallpaper for the shared tile/detail components.
    func asWallpaper() -> Wallpaper {
        Wallpaper(
            id: id, slug: slug, userID: 0, categoryID: nil, title: title, description: "",
            originalURL: originalURL, thumbURL: thumbURL, previewURL: previewURL,
            width: width, height: height, fileSize: fileSize, fileType: fileType,
            dominantColor: dominantColor, colorPalette: colorPalette, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: isDynamic,
            isAIGenerated: isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}

// Specific week's full pick set. Loads /weekly-picks/:year/:week and
// renders an editorial header + grid.
struct WeeklyWeekView: View {
    let year: Int
    let week: Int
    var onWallpaper: WallpaperSelectionHandler

    @State private var picks: [WeeklyPicked] = []
    @State private var loading = false
    @State private var loadError: String?

    private var hero: WeeklyPicked? { picks.first(where: { $0.isHero }) ?? picks.first }
    private var navigationItems: [Wallpaper] { picks.map(asWallpaper) }
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 16, alignment: .top)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.home.weekTitle(week)).font(.display32).foregroundStyle(Color.ink)
                    Text("\(WeeklyArchiveView.fmtDate(year, week)), \(String(year))")
                        .font(.mono11).tracking(0.6).foregroundStyle(Color.muted)
                }
                .padding(.top, 10)

                if loading && picks.isEmpty {
                    weekSkeleton.padding(.top, 28)
                } else if let err = loadError, picks.isEmpty {
                    RemoteLoadErrorView(message: err) {
                        Task { await load() }
                    }
                } else {
                    if let h = hero { heroCard(h).padding(.top, 28) }
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(picks) { p in
                            Button(action: { onWallpaper(asWallpaper(p), navigationItems) }) {
                                MainGridTile(wallpaper: asWallpaper(p), aspectRatio: 4.0 / 5.0)
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                if h { PaletteEnv.shared.apply(palette: p.colorPalette, dominant: p.dominantColor) }
                                else { applyHeroPalette() }
                            }
                        }
                    }
                    .padding(.top, 32)
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task(id: "\(year)-\(week)") { await load() }
        .onAppear { applyHeroPalette() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var weekSkeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            SkeletonPlate(aspectRatio: 16.0 / 9.0, cornerRadius: 18)
            WallpaperGridSkeleton(columns: gridColumns, count: 12, spacing: 16, aspectRatio: 4.0 / 5.0, cornerRadius: 10)
        }
    }

    // Masthead hero — the issue's hero pick, 16:9, with a curation
    // overlay + trade CTA (mirrors the web/home hero card).
    private func heroCard(_ h: WeeklyPicked) -> some View {
        Button(action: { onWallpaper(asWallpaper(h), navigationItems) }) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    ProgressiveCachedAsyncImage(
                        lowURL: cleanURL(h.previewURL.isEmpty ? h.thumbURL : h.previewURL),
                        highURL: cleanURL(h.originalURL),
                        lowMaxPixelDimension: 1400,
                        highMaxPixelDimension: 4200
                    ) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color(hex: h.dominantColor ?? "#bbb").opacity(0.5) }
                }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.home.heroKicker(week, year))
                                .font(.kicker).tracking(2.0).foregroundStyle(.white.opacity(0.9))
                            Text("\(h.width)×\(h.height) · \(mb(h.fileSize))")
                                .font(.mono11).tracking(0.5).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Circle().fill(Color.accent).frame(width: 9, height: 9)
                            Text(L10n.home.tradeForOne).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                    }
                    .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyHeroPalette() {
        if let h = hero { PaletteEnv.shared.apply(palette: h.colorPalette, dominant: h.dominantColor) }
        else { PaletteEnv.shared.resetToDefaults() }
    }
    private func mb(_ b: Int) -> String { String(format: "%.1f MB", Double(b) / 1024 / 1024) }

    private func cleanURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    private func load() async {
        loadError = nil
        loading = true; defer { loading = false }
        do {
            let data = try await APIClient.shared.fetchWeeklyByWeek(year: year, week: week)
            picks = data.picks
            applyHeroPalette()
        } catch {
            loadError = error.localizedDescription
        }
    }

    // Shared converter lives in the WeeklyPicked extension below.
    private func asWallpaper(_ p: WeeklyPicked) -> Wallpaper {
        p.asWallpaper()
    }
}
