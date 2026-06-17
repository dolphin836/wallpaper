import SwiftUI
import AppKit

// The single root popover view. Layout per the design hand-off in
// docs/design_handoff_macos/:
//
//   ┌─ Header (64 px)         ─ avatar + name + coin pill + logout
//   ├─ Body                    ─ Latest │ Downloaded (hairline divider)
//   └─ Footer (44 px)          ─ Quit · Open in browser · version
//
// Total surface 720 × 700 px. NSPopover supplies the rounded-rect chrome
// and the menu-bar tail; we paint the paper-tinted frosted glass
// underneath via NSVisualEffectView.
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
    @State private var latestMacOnly = false
    @State private var downloadedMacOnly = false

    private var screenSize: (width: Int, height: Int) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let dpr = Int(screen.backingScaleFactor)
        return (Int(screen.frame.width) * dpr, Int(screen.frame.height) * dpr)
    }

    var body: some View {
        ZStack {
            // Paper-tinted frosted backdrop. Layered as ZStack rather than
            // .background so it covers the full popover content area
            // including under translucent header/footer fills.
            VisualEffectBackground()
            Color.paper.opacity(0.55)

            VStack(spacing: 0) {
                PopoverHeaderView(auth: auth)

                Rectangle().fill(Color.hair).frame(height: 1)

                if let msg = errorMessage {
                    errorBar(msg)
                }

                HStack(alignment: .top, spacing: 0) {
                    WallpaperColumnView(
                        title: "Latest",
                        icon: "bolt.fill",
                        wallpapers: filteredLatest,
                        isLoading: isLoadingLatest,
                        hasMore: latestHasMore,
                        kind: .latest,
                        manager: manager,
                        macOnly: latestMacOnly,
                        onMacOnlyToggle: { latestMacOnly.toggle() },
                        shuffleOn: false,
                        hasShuffle: false,
                        onShuffleToggle: nil,
                        shuffleNextAt: nil,
                        onOpenLocalFolder: nil,
                        emptyTitle: "No wallpapers",
                        emptySubtitle: nil,
                        onDownload: { wp in Task { await download(wp) } },
                        onRedownload: { _ in },
                        onLoadMore: { Task { await loadLatest() } }
                    )

                    Rectangle().fill(Color.hair).frame(width: 1)

                    WallpaperColumnView(
                        title: "Downloaded",
                        icon: "arrow.down.to.line",
                        wallpapers: filteredDownloaded,
                        isLoading: isLoadingDownloaded,
                        hasMore: downloadedHasMore,
                        kind: .downloaded,
                        manager: manager,
                        macOnly: downloadedMacOnly,
                        onMacOnlyToggle: { downloadedMacOnly.toggle() },
                        shuffleOn: manager.autoRotate,
                        hasShuffle: true,
                        onShuffleToggle: { manager.setAutoRotate(!manager.autoRotate) },
                        shuffleNextAt: manager.nextRotationAt,
                        onOpenLocalFolder: { revealDownloadsFolder() },
                        emptyTitle: "No downloads yet",
                        emptySubtitle: "Try a wallpaper from Latest. Open a wallpaper detail page to set it.",
                        onDownload: { _ in },
                        onRedownload: { wp in Task { await download(wp) } },
                        onLoadMore: { Task { await loadDownloaded() } }
                    )
                }
                .frame(maxHeight: .infinity)

                PopoverFooterView(
                    onOpenWeb: openWeb,
                    localStorageBytes: manager.totalLocalBytes
                )
            }
        }
        .frame(width: 720, height: 700)
        .task { await loadAll() }
        .onChange(of: auth.isLoggedIn) { _, _ in Task { await loadAll() } }
        .onChange(of: latestMacOnly) { _, _ in Task { await loadLatest(reset: true) } }
        .onChange(of: downloadedMacOnly) { _, _ in Task { await loadDownloaded(reset: true) } }
        .overlay {
            if let flow = auth.authFlow {
                AuthModalOverlay(mode: flow)
                    .id(flow.id)
                    .transition(.opacity)
            }
        }
    }

    // ─── Sub-views ─────────────────────────────────────────────────

    private func errorBar(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Color.warn)
            Text(msg)
                .font(.sans11)
                .foregroundStyle(Color.ink2)
                .lineLimit(2)
            Spacer()
            Button("Retry") { Task { await loadAll() } }
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(Color.warn.opacity(0.06))
    }

    // ─── Derived views over the wallpaper lists ─────────────────────

    // Client-side dynamic-only filter. The server-side filter is also
    // applied via the dynamicOnly query param (set when the toggle is on);
    // this just keeps the current page consistent if the user flips the
    // toggle between fetches.
    private var filteredLatest: [Wallpaper] {
        latestMacOnly ? latestWallpapers.filter { $0.isDynamic } : latestWallpapers
    }
    private var filteredDownloaded: [Wallpaper] {
        downloadedMacOnly ? downloadedWallpapers.filter { $0.isDynamic } : downloadedWallpapers
    }

    private func openWeb() {
        if let url = URL(string: "https://wallpaperexchange.com") {
            NSWorkspace.shared.open(url)
        }
    }

    // Open the local downloads directory in a Finder window. activateFileViewer
    // (vs. plain `open`) makes Finder surface the folder even if it's empty,
    // which is the common case on a fresh install before the first download.
    private func revealDownloadsFolder() {
        let url = manager.storagePath
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Data loading

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
            let data = try await APIClient.shared.fetchWallpapers(
                cursor: reset ? nil : latestCursor,
                limit: 20,
                dynamicOnly: latestMacOnly
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
            // Keep the endpoint's optional exact-device variant filter off
            // here so downloads mirror the server-side library.
            let data = try await APIClient.shared.fetchMyDownloads(
                cursor: reset ? nil : downloadedCursor,
                limit: 20,
                dynamicOnly: downloadedMacOnly
            )
            if reset {
                downloadedWallpapers = data.items
            } else {
                downloadedWallpapers.append(contentsOf: data.items)
            }
            downloadedCursor = data.nextCursor
            downloadedHasMore = data.hasMore
        } catch {
            if case APIError.unauthorized = error { auth.logout() }
        }
    }

    // MARK: - Actions

    private func download(_ wallpaper: Wallpaper) async {
        guard auth.isLoggedIn else { auth.login(); return }
        do {
            try await manager.download(wallpaper: wallpaper)
            await auth.refreshProfile()
            await loadDownloaded(reset: true)
        } catch APIError.insufficientCoins {
            errorMessage = "Insufficient coins. Upload wallpapers to earn more!"
        } catch APIError.unauthorized {
            auth.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
