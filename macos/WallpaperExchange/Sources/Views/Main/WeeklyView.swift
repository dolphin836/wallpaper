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
    @State private var selectedIdx = 0

    private var selected: WeeklyArchiveEntry? {
        entries.indices.contains(selectedIdx) ? entries[selectedIdx] : entries.first
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
                    Text("No weekly drops have been published yet.")
                        .font(.sans13).foregroundStyle(Color.muted).padding(.top, 20)
                } else {
                    HStack(alignment: .top, spacing: 36) {
                        timeline.frame(width: 240)
                        coverPanel
                    }
                    .padding(.top, 36)
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await load() }
        .onChange(of: selectedIdx) { _, _ in applySelectedPalette() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var archiveSkeleton: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        SkeletonPlate(aspectRatio: 1, cornerRadius: 4, shadow: false)
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
            Kicker(text: "The Archive")
            Text("Every Friday, a new ten.")
                .font(.display32).foregroundStyle(Color.ink)
            Text("We publish ten wallpapers each ISO week. Once a piece lands in a drop it never returns. Pick an issue from the timeline.")
                .font(.sans13).foregroundStyle(Color.ink2)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                let on = i == selectedIdx
                Button { selectedIdx = i } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(on ? Color.accent : Color.hair)
                            .frame(width: 7, height: 7)
                        Text("№ \(String(format: "%02d", e.week))")
                            .font(.system(size: 13, weight: on ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(on ? Color.ink : Color.ink2)
                        Spacer(minLength: 0)
                        Text("\(Self.fmtDate(e.year, e.week)) · \(String(e.year))")
                            .font(.mono10).tracking(0.4).foregroundStyle(Color.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.accent.opacity(0.10) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    if h { PaletteEnv.shared.apply(palette: e.colorPalette, dominant: e.dominantColor) }
                    else { applySelectedPalette() }
                }
            }
        }
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
                                CachedAsyncImage(url: URL(string: s.coverURL)) { img in
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
                                    Text("ISSUE").font(.kicker).tracking(2.4).foregroundStyle(.white.opacity(0.85))
                                    Text("№ \(String(format: "%02d", s.week))")
                                        .font(.system(size: 30, weight: .semibold, design: .serif))
                                        .foregroundStyle(.white)
                                    Text("\(Self.fmtDate(s.year, s.week)) \(String(s.year)) · \(s.count) PICKS")
                                        .font(.mono11).tracking(0.6).foregroundStyle(.white.opacity(0.85))
                                }
                                .padding(20)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hair, lineWidth: 1))

                        HStack(spacing: 8) {
                            Text("View all \(s.count) picks")
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
            entries = try await APIClient.shared.fetchWeeklyArchive(limit: 100)
            applySelectedPalette()
        } catch {
            loadError = error.localizedDescription
        }
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
                    Text("Week \(week)").font(.display32).foregroundStyle(Color.ink)
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
            .frame(maxWidth: 1280).frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task(id: "\(year)-\(week)") { await load() }
        .onAppear { applyHeroPalette() }
        .onDisappear { PaletteEnv.shared.resetToDefaults() }
    }

    private var weekSkeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            SkeletonPlate(aspectRatio: 16.0 / 9.0, cornerRadius: 16)
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
                    CachedAsyncImage(url: URL(string: h.previewURL.isEmpty ? h.originalURL : h.previewURL)) { img in
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
                            Text("CURATION · WEEK \(week) · \(String(year))")
                                .font(.kicker).tracking(2.0).foregroundStyle(.white.opacity(0.9))
                            Text("\(h.width)×\(h.height) · \(mb(h.fileSize))")
                                .font(.mono11).tracking(0.5).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Circle().fill(Color.accent).frame(width: 9, height: 9)
                            Text("Trade for 1").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                    }
                    .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyHeroPalette() {
        if let h = hero { PaletteEnv.shared.apply(palette: h.colorPalette, dominant: h.dominantColor) }
        else { PaletteEnv.shared.resetToDefaults() }
    }
    private func mb(_ b: Int) -> String { String(format: "%.1f MB", Double(b) / 1024 / 1024) }

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
