import SwiftUI

struct WeeklyTabView: View {
    @Environment(UIPrefs.self) private var prefs

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: L10n.strings(for: prefs.language).weekly)
                WeeklyArchiveView(showNavigationBar: false)
            }
            .background(PageMesh())
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .safeAreaInset(edge: .bottom) { FloatingTabBar() }
            .navigationDestination(for: WeeklyArchiveEntry.self) { entry in
                WeeklyWeekView(year: entry.year, week: entry.week)
            }
        }
    }
}

// Weekly archive — pushed from Home's "See all". The current slate
// lives on Home; this page is the back catalogue of past weeks.
struct WeeklyArchiveView: View {
    var showNavigationBar = true

    @Environment(UIPrefs.self) private var prefs

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
                    archiveSkeleton
                }
            }
            .padding(.top, 8)
        }
        .background(PageMesh())
        .navigationTitle(L10n.strings(for: prefs.language).weekly)
        .inlineNavTitle()
        .modifier(WeeklyArchiveNavModifier(showNavigationBar: showNavigationBar))
        .refreshable { await load() }
        .task { if archive.isEmpty { await load() } }
    }

    private var archiveSection: some View {
        let s = L10n.strings(for: prefs.language)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(kicker: s.weeklyArchiveKicker, title: s.pastWeeks)
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

    private var archiveSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(radius: 3).frame(width: 86, height: 9)
                SkeletonBlock(radius: 5).frame(width: 150, height: 20)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    WeeklyArchiveCardSkeleton()
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func archiveCard(_ entry: WeeklyArchiveEntry) -> some View {
        let s = L10n.strings(for: prefs.language)
        let accent = Color(hex: entry.accentColor ?? entry.dominantColor) ?? Color.accent

        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.18))
                .offset(x: 7, y: -7)

            Color.clear
                .aspectRatio(0.78, contentMode: .fit)
                .overlay(
                    LoadingCoverImage(url: URL(string: entry.coverURL), maxPixelDimension: 800) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(accent.opacity(0.72))
                    }
                )
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.08), .black.opacity(0.72)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(String(format: s.week, entry.week))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.lightText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MediaChip(text: String(format: s.year, entry.year), tint: .black.opacity(0.20))
                    MediaChip(text: String(format: s.picksCount, entry.count), tint: .black.opacity(0.20))
                }
            }
            .padding(12)
        }
        .shadow(color: accent.opacity(0.18), radius: 16, y: 8)
        .paletteReactive(palette: entry.colorPalette, dominant: entry.dominantColor ?? entry.accentColor)
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

private struct WeeklyArchiveNavModifier: ViewModifier {
    let showNavigationBar: Bool

    func body(content: Content) -> some View {
        if showNavigationBar {
            content.showNavBarCompat()
        } else {
            content.hideNavBarCompat()
        }
    }
}

// One archived week's full pick set.
struct WeeklyWeekView: View {
    let year: Int
    let week: Int

    @State private var picks: [WeeklyPicked] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if let loadError, picks.isEmpty {
                ErrorRetryView(message: loadError) { Task { await load() } }
            } else if picks.isEmpty && loading {
                WallpaperGridSkeleton(count: 8)
                    .padding(.top, 8)
            } else {
                WallpaperGrid(wallpapers: picks.map(\.asWallpaper).filter(\.isUsableOnIOS), showsEndState: false)
                    .padding(.top, 8)
            }
        }
        .background(PageMesh())
        .navigationTitle("Week \(week) · \(String(year))")
        .inlineNavTitle()
        .showNavBarCompat()
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                LockPreviewToolbarButton()
            }
            #endif
        }
        .task { if picks.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            picks = try await APIClient.shared.fetchWeeklyByWeek(year: year, week: week).picks
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct WeeklyArchiveCardSkeleton: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SkeletonBlock(radius: 18)
                .offset(x: 7, y: -7)
                .opacity(0.46)

            SkeletonBlock(radius: 18)
                .aspectRatio(0.78, contentMode: .fit)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(radius: 5).frame(width: 82, height: 18)
                HStack(spacing: 6) {
                    SkeletonBlock(radius: 6).frame(width: 54, height: 18)
                    SkeletonBlock(radius: 6).frame(width: 66, height: 18)
                }
            }
            .padding(12)
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
