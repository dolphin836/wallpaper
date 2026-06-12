import SwiftUI

// Weekly archive — pushed from Home's "See all". The current slate
// lives on Home; this page is the back catalogue of past weeks.
struct WeeklyArchiveView: View {
    @State private var archive: [WeeklyArchiveEntry] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let loadError, archive.isEmpty {
                    ErrorRetryView(message: loadError) { Task { await load() } }
                } else if !archive.isEmpty {
                    archiveSection
                } else if loading {
                    LoadingFooter()
                }
            }
            .padding(.top, 8)
        }
        .background(Color.paper)
        .navigationTitle("Weekly Picks")
        .inlineNavTitle()
        .refreshable { await load() }
        .task { if archive.isEmpty { await load() } }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: "The back catalogue", title: "Past Weeks")
                .padding(.horizontal, 12)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(archive) { entry in
                    NavigationLink(value: entry) {
                        archiveCard(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func archiveCard(_ entry: WeeklyArchiveEntry) -> some View {
        CachedAsyncImage(url: URL(string: entry.coverURL), maxPixelDimension: 700) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color(hex: entry.accentColor ?? entry.dominantColor) ?? Color.paper3)
        }
        .aspectRatio(1.4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Week \(entry.week)")
                    .font(.subheadline.weight(.semibold))
                Text("\(String(entry.year)) · \(entry.count) picks")
                    .font(.caption2)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            archive = try await APIClient.shared.fetchWeeklyArchive(limit: 30)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// One archived week's full pick set.
struct WeeklyWeekView: View {
    let year: Int
    let week: Int

    @State private var picks: [WeeklyPicked] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if let loadError, picks.isEmpty {
                ErrorRetryView(message: loadError) { Task { await load() } }
            } else {
                WallpaperGrid(wallpapers: picks.map(\.asWallpaper).filter(\.isUsableOnIOS))
                    .padding(.top, 8)
            }
        }
        .background(Color.paper)
        .navigationTitle("Week \(week) · \(String(year))")
        .inlineNavTitle()
        .task { if picks.isEmpty { await load() } }
    }

    private func load() async {
        do {
            picks = try await APIClient.shared.fetchWeeklyByWeek(year: year, week: week).picks
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

extension WeeklyPicked {
    // WeeklyPicked carries a Wallpaper subset; lift it into the shared
    // grid's shape so weekly pages reuse the same tile + detail route.
    var asWallpaper: Wallpaper {
        Wallpaper(
            id: id, slug: slug, userID: 0, categoryID: nil,
            title: title, description: "",
            originalURL: originalURL, thumbURL: thumbURL, previewURL: previewURL,
            width: width, height: height, fileSize: fileSize, fileType: fileType,
            dominantColor: dominantColor, colorPalette: colorPalette,
            status: 1, viewCount: 0, likeCount: 0, downloadCount: 0, favoriteCount: 0,
            isDynamic: isDynamic, isAIGenerated: isAIGenerated,
            isLiked: nil, isFavorited: nil, isDownloaded: nil,
            createdAt: ""
        )
    }
}
