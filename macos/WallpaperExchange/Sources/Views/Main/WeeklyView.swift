import AppKit
import SwiftUI

// Weekly Picks archive — mirrors the web: an editorial header, a
// left-hand timeline of past issues, and a large cover panel for the
// selected issue (stamp + "view all N picks" CTA). Selecting a
// timeline row swaps the cover; clicking the cover opens that week.
struct WeeklyArchiveView: View {
    var onOpenWeek: (Int, Int) -> Void

    @State private var entries: [WeeklyArchiveEntry] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var selectedID: String?

    private var selected: WeeklyArchiveEntry? {
        if let selectedID, let entry = entries.first(where: { $0.id == selectedID }) {
            return entry
        }
        return entries.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if loading && entries.isEmpty {
                    archiveSkeleton.padding(.top, 36)
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
                    HStack(alignment: .top, spacing: 36) {
                        timeline
                            .frame(width: 240)
                            .zIndex(2)
                        coverPanel
                            .zIndex(1)
                    }
                    .padding(.top, 36)
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
        .onChange(of: selectedID) { _, _ in applySelectedPalette() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var archiveSkeleton: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SkeletonPlate(aspectRatio: 1, cornerRadius: 6, shadow: false)
                            .frame(width: 7, height: 7)
                        SkeletonLine(width: 68, height: 13)
                        Spacer(minLength: 0)
                        SkeletonLine(width: 92, height: 10)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }
            .frame(width: 240)
            VStack(alignment: .leading, spacing: 14) {
                SkeletonPlate(aspectRatio: 16.0 / 10.0, cornerRadius: 14)
                SkeletonLine(width: 148, height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Tint the page mesh to the selected issue (hover temporarily
    // overrides it; leaving a row falls back here).
    private func applySelectedPalette() {
        if let s = selected {
            PaletteEnv.shared.apply(palette: s.colorPalette, dominant: s.dominantColor)
        } else {
            PaletteEnv.shared.resetToDefaults()
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

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { e in
                let on = e.id == selected?.id
                WeeklyTimelineRow(entry: e, selected: on, dateText: Self.fmtDate(e.year, e.week))
                    .frame(width: 240, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(Color.black.opacity(0.001))
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            select(e)
                        }
                    )
                    // Hover only changes the cursor. The page mesh follows
                    // the *selected* issue (see select() / applySelectedPalette),
                    // not whatever row the pointer is over — tinting on hover
                    // made the background flicker while scanning the timeline.
                    .onHover { h in
                        if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
        }
    }

    private func select(_ entry: WeeklyArchiveEntry) {
        withAnimation(.easeOut(duration: 0.18)) {
            selectedID = entry.id
        }
        PaletteEnv.shared.apply(palette: entry.colorPalette, dominant: entry.dominantColor)
    }

    private var coverPanel: some View {
        Group {
            if let s = selected {
                Button { onOpenWeek(s.year, s.week) } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        // Color.clear sets a strict 16:10 box; the cover
                        // fills it as an overlay and is clipped, so a
                        // large image can't overflow the panel.
                        Color.clear
                            .aspectRatio(16.0 / 10.0, contentMode: .fit)
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
                                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                               startPoint: .center, endPoint: .bottom)
                                    .allowsHitTesting(false)
                            }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.home.issueLabel).font(.kicker).tracking(2.4).foregroundStyle(.white.opacity(0.85))
                                    Text("№ \(String(format: "%02d", s.week))")
                                        .font(.system(size: 30, weight: .semibold, design: .serif))
                                        .foregroundStyle(.white)
                                    Text("\(Self.fmtDate(s.year, s.week)) \(String(s.year)) · \(L10n.home.picksCountCaps(s.count))")
                                        .font(.mono11).tracking(0.6).foregroundStyle(.white.opacity(0.85))
                                }
                                .padding(20)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hair, lineWidth: 1))
                            .id(s.id)

                        HStack(spacing: 8) {
                            Text(L10n.home.viewAllPicks(s.count))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accent)
                            Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        loadError = nil
        loading = true; defer { loading = false }
        do {
            let loaded = try await APIClient.shared.fetchWeeklyArchive(limit: 100)
            entries = loaded
            if let selectedID, loaded.contains(where: { $0.id == selectedID }) == false {
                self.selectedID = loaded.first?.id
            } else if selectedID == nil {
                selectedID = loaded.first?.id
            }
            applySelectedPalette()
        } catch {
            loadError = error.localizedDescription
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

private struct WeeklyTimelineRow: View {
    let entry: WeeklyArchiveEntry
    let selected: Bool
    let dateText: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(selected ? Color.accent : Color.hair)
                .frame(width: 7, height: 7)
            Text("№ \(String(format: "%02d", entry.week))")
                .font(.system(size: 13, weight: selected ? .semibold : .medium, design: .monospaced))
                .foregroundStyle(selected ? Color.ink : Color.ink2)
            Spacer(minLength: 0)
            Text("\(dateText) · \(String(entry.year))")
                .font(.mono10)
                .tracking(0.4)
                .foregroundStyle(Color.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accent.opacity(0.10) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// Specific week's full pick set. Loads /weekly-picks/:year/:week and
// renders an editorial header + grid.
struct WeeklyWeekView: View {
    let year: Int
    let week: Int
    var onWallpaper: (Wallpaper) -> Void

    @State private var picks: [WeeklyPicked] = []
    @State private var loading = false
    @State private var loadError: String?

    private var hero: WeeklyPicked? { picks.first(where: { $0.isHero }) ?? picks.first }
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
                            Button(action: { onWallpaper(asWallpaper(p)) }) {
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
        Button(action: { onWallpaper(asWallpaper(h)) }) {
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

    // WeeklyPicked → Wallpaper for the shared tile component.
    private func asWallpaper(_ p: WeeklyPicked) -> Wallpaper {
        Wallpaper(
            id: p.id, slug: p.slug, userID: 0, categoryID: nil, title: p.title, description: "",
            originalURL: p.originalURL, thumbURL: p.thumbURL, previewURL: p.previewURL,
            width: p.width, height: p.height, fileSize: p.fileSize, fileType: p.fileType,
            dominantColor: p.dominantColor, colorPalette: p.colorPalette, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: p.isDynamic,
            isAIGenerated: p.isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}
