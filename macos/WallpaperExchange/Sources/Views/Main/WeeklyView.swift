import SwiftUI

// Weekly Picks archive — list of past weekly slates. Clicking one
// opens WeeklyWeekView with the full pick set for that week.
struct WeeklyArchiveView: View {
    var onOpenWeek: (Int, Int) -> Void

    @State private var entries: [WeeklyArchiveEntry] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Editor-curated · every Friday")
                    Text("Weekly Picks").font(.display32).foregroundStyle(Color.ink)
                }

                if loading && entries.isEmpty {
                    ProgressView().padding(.top, 30)
                } else if let err = loadError {
                    Text(err).font(.sans12).foregroundStyle(Color.warn)
                } else if entries.isEmpty {
                    Text("No archive yet.")
                        .font(.sans13).foregroundStyle(Color.muted)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 18, alignment: .top)], spacing: 18) {
                        ForEach(entries) { entry in
                            Button(action: { onOpenWeek(entry.year, entry.week) }) {
                                ArchiveCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            entries = try await APIClient.shared.fetchWeeklyArchive(limit: 50)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ArchiveCard: View {
    let entry: WeeklyArchiveEntry
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL(string: entry.coverURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(hex: entry.dominantColor ?? "#bbb").opacity(0.5)
                }
                .aspectRatio(3 / 2, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEK \(entry.week) · \(entry.year)")
                        .font(.kicker).tracking(2.2)
                        .foregroundStyle(.white.opacity(0.92))
                    Text("\(entry.count) wallpapers")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                }
                .padding(14)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1).allowsHitTesting(false))
        }
        .scaleEffect(hover ? 1.01 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.10 : 0), radius: 12, x: 0, y: 6)
        .animation(.easeOut(duration: 0.18), value: hover)
        .onHover { hover = $0 }
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Week \(week) · \(year)")
                    Text("This week's picks")
                        .font(.display32).foregroundStyle(Color.ink)
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }

                if loading && picks.isEmpty {
                    ProgressView().padding(.top, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(picks) { p in
                            Button(action: { onWallpaper(asWallpaper(p)) }) {
                                MainGridTile(wallpaper: asWallpaper(p))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        // page-mesh shows through; no opaque paper background here
        .task(id: "\(year)-\(week)") { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let data = try? await APIClient.shared.fetchWeeklyByWeek(year: year, week: week) {
            picks = data.picks
        }
    }

    // WeeklyPicked → Wallpaper for the shared tile component.
    private func asWallpaper(_ p: WeeklyPicked) -> Wallpaper {
        Wallpaper(
            id: p.id, slug: p.slug, userID: 0, categoryID: nil, title: p.title, description: "",
            originalURL: p.originalURL, thumbURL: p.thumbURL, previewURL: p.previewURL,
            width: p.width, height: p.height, fileSize: p.fileSize, fileType: p.fileType,
            dominantColor: p.dominantColor, colorPalette: nil, status: 1, viewCount: 0, likeCount: 0,
            downloadCount: 0, favoriteCount: 0, isDynamic: p.isDynamic,
            isAIGenerated: p.isAIGenerated, isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}
