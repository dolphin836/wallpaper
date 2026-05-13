import SwiftUI
import AppKit

struct PopoverContentView: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared

    @State private var latestWallpapers: [Wallpaper] = []
    @State private var downloadedWallpapers: [Wallpaper] = []
    @State private var latestCursor: Int?
    @State private var latestHasMore = false
    @State private var downloadedCursor: Int?
    @State private var downloadedHasMore = false
    @State private var isLoadingLatest = false
    @State private var isLoadingDownloaded = false
    @State private var errorMessage: String?

    private var screenSize: (width: Int, height: Int) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let dpr = Int(screen.backingScaleFactor)
        return (
            Int(screen.frame.width) * dpr,
            Int(screen.frame.height) * dpr
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            UserBarView(auth: auth)

            Divider()

            if let msg = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await loadAll() } }
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            HStack(alignment: .top, spacing: 0) {
                wallpaperColumn(
                    title: "Latest",
                    icon: "sparkles",
                    wallpapers: latestWallpapers,
                    isLoading: isLoadingLatest,
                    hasMore: latestHasMore,
                    isLocal: false,
                    onLoadMore: { Task { await loadLatest() } }
                )

                Divider()

                wallpaperColumn(
                    title: "Downloaded",
                    icon: "arrow.down.circle",
                    wallpapers: downloadedWallpapers,
                    isLoading: isLoadingDownloaded,
                    hasMore: downloadedHasMore,
                    isLocal: true,
                    onLoadMore: { Task { await loadDownloaded() } }
                )
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                        Text("Quit")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://wallpaperexchange.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 10))
                        Text("Open Web")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open wallpaperexchange.com in your browser")

                Spacer()

                Text("Wallpaper Exchange")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 600, height: 500)
        .task {
            await loadAll()
        }
        // Auth state can change at any time (Sign In / Sign Out / token invalidated by an
        // API 401). Re-running loadAll wipes any state that's no longer authorized to be
        // shown (e.g. the Downloaded list after a logout) and fetches fresh data once
        // logged in again.
        .onChange(of: auth.isLoggedIn) { _, _ in
            Task { await loadAll() }
        }
    }

    private func wallpaperColumn(
        title: String,
        icon: String,
        wallpapers: [Wallpaper],
        isLoading: Bool,
        hasMore: Bool,
        isLocal: Bool,
        onLoadMore: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(wallpapers) { wp in
                        WallpaperRow(
                            wallpaper: wp,
                            column: isLocal ? .downloaded : .latest,
                            isDownloading: manager.downloading.contains(wp.id),
                            onDownload: { Task { await download(wp) } },
                            onDownloadAndSet: { Task { await downloadAndSet(wp) } },
                            onSetWallpaper: { setWallpaper(wp.id) }
                        )
                    }

                    if hasMore {
                        Button("Load more") { onLoadMore() }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }

                    if !isLoading && wallpapers.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: isLocal ? "tray" : "photo.on.rectangle.angled")
                                .font(.system(size: 24))
                                .foregroundStyle(.quaternary)
                            Text(isLocal ? "No downloads yet" : "No wallpapers")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadAll() async {
        latestWallpapers = []
        downloadedWallpapers = []
        latestCursor = nil
        downloadedCursor = nil
        errorMessage = nil
        await loadLatest(reset: true)
        if auth.isLoggedIn {
            await loadDownloaded(reset: true)
            await auth.refreshProfile()
        }
    }

    private func loadLatest(reset: Bool = false) async {
        guard !isLoadingLatest else { return }
        isLoadingLatest = true
        defer { isLoadingLatest = false }

        do {
            let size = screenSize
            let data = try await APIClient.shared.fetchWallpapers(
                cursor: reset ? nil : latestCursor,
                limit: 20,
                deviceWidth: size.width,
                deviceHeight: size.height
            )
            if reset {
                latestWallpapers = data.items
            } else {
                latestWallpapers.append(contentsOf: data.items)
            }
            latestCursor = data.nextCursor
            latestHasMore = data.hasMore
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDownloaded(reset: Bool = false) async {
        guard auth.isLoggedIn, !isLoadingDownloaded else { return }
        isLoadingDownloaded = true
        defer { isLoadingDownloaded = false }

        do {
            let data = try await APIClient.shared.fetchMyDownloads(
                cursor: reset ? nil : downloadedCursor,
                limit: 20
            )
            if reset {
                downloadedWallpapers = data.items
            } else {
                downloadedWallpapers.append(contentsOf: data.items)
            }
            downloadedCursor = data.nextCursor
            downloadedHasMore = data.hasMore
        } catch {
            if case APIError.unauthorized = error {
                auth.logout()
            }
        }
    }

    // MARK: - Actions

    private func download(_ wallpaper: Wallpaper) async {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        do {
            try await manager.download(wallpaper: wallpaper)
            await auth.refreshProfile()
            // The right-hand "Downloaded" column is sourced from /users/me/downloads,
            // not from WallpaperManager's local file scan — so the freshly-recorded
            // download won't appear until we re-fetch that list.
            await loadDownloaded(reset: true)
        } catch APIError.insufficientCoins {
            errorMessage = "Insufficient coins. Upload wallpapers to earn more!"
        } catch APIError.unauthorized {
            auth.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Download then immediately apply as desktop wallpaper. Errors during the apply
    // step still surface but don't roll back the download (file stays on disk).
    private func downloadAndSet(_ wallpaper: Wallpaper) async {
        guard auth.isLoggedIn else {
            auth.login()
            return
        }
        do {
            try await manager.download(wallpaper: wallpaper)
            await auth.refreshProfile()
            await loadDownloaded(reset: true)
            try manager.setAsWallpaper(wallpaper.id)
        } catch APIError.insufficientCoins {
            errorMessage = "Insufficient coins. Upload wallpapers to earn more!"
        } catch APIError.unauthorized {
            auth.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setWallpaper(_ id: Int) {
        do {
            try manager.setAsWallpaper(id)
        } catch {
            errorMessage = "Failed to set wallpaper: \(error.localizedDescription)"
        }
    }
}
