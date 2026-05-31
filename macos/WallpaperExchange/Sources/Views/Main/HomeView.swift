import SwiftUI

// Home tab — editorial landing. Top kicker + serif headline + intro,
// then a 'This week's picks' hero rail, then a recent grid. Mirrors the
// web's home page (Layout pulls /weekly-picks/current + recent).
struct HomeView: View {
    var onPick: (Wallpaper) -> Void
    var onOpenWeek: (Int, Int) -> Void

    @State private var current: WeeklyCurrent?
    @State private var recent: [Wallpaper] = []
    @State private var loading = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                hero
                weeklyRail
                recentSection
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 60)
        }
        .task { await load() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "Today · curated")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Find something for your")
                    .font(.display32).foregroundStyle(Color.ink)
                Text("Mac.").font(.display32).foregroundStyle(Color.accent)
            }
            Text("Hand-picked wallpapers from the community. Hover a tile for one-click set, or open detail for full controls.")
                .font(.sans13).foregroundStyle(Color.muted)
                .frame(maxWidth: 580, alignment: .leading)
        }
    }

    private var weeklyRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: current.map { "Week \($0.week) · \($0.year)" } ?? "Latest weekly")
                Spacer()
                if let c = current {
                    Button(action: { onOpenWeek(c.year, c.week) }) {
                        Text("VIEW WEEK →")
                            .font(.kicker).tracking(1.8)
                            .foregroundStyle(Color.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("This week's picks").font(.display24).foregroundStyle(Color.ink)
            if let picks = current?.picks, !picks.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10, alignment: .top)],
                    spacing: 10
                ) {
                    ForEach(picks.prefix(6)) { p in
                        let wp = asWallpaper(p)
                        Button(action: { onPick(wp) }) {
                            MainGridTile(wallpaper: wp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if loading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 60)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Kicker(text: "Latest · what just landed")
                Spacer()
            }
            Text("Recent uploads").font(.display24).foregroundStyle(Color.ink)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .top)],
                spacing: 12
            ) {
                ForEach(recent) { wp in
                    Button(action: { onPick(wp) }) { MainGridTile(wallpaper: wp) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let weeklyTask: WeeklyCurrent? = try? await APIClient.shared.fetchWeeklyCurrent()
        async let recentTask: PaginatedData<Wallpaper>? = try? await APIClient.shared.fetchWallpapers(limit: 18)
        let (weekly, recentData) = await (weeklyTask, recentTask)
        current = weekly
        recent = recentData?.items ?? []
    }

    private func asWallpaper(_ p: WeeklyPicked) -> Wallpaper {
        Wallpaper(
            id: p.id, slug: p.slug, userID: 0, categoryID: nil, title: p.title, description: "",
            originalURL: p.originalURL, thumbURL: p.thumbURL, previewURL: p.previewURL,
            width: p.width, height: p.height, fileSize: p.fileSize, fileType: p.fileType,
            dominantColor: p.dominantColor, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: p.isDynamic,
            isAIGenerated: p.isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}
