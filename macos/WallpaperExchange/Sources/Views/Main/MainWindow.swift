import SwiftUI
import AppKit

// v2.2 main window. Left sidebar (Browse + My Library + footer
// identity cell) and a thin top toolbar above the content area.
// Full-page push for detail / profile / collection / device / etc.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared
    @ObservedObject private var metrics = WindowMetrics.shared

    @State private var sidebar: SidebarItem = .home
    @State private var sidebarCollapsed = false
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var committedSearch: String = ""
    @State private var showingUpload = false

    enum SidebarItem: String, CaseIterable, Hashable {
        // Browse section.
        case home, discover, weekly, collections
        // My Library section (signed-in only).
        case myUploads, myCollections, myDownloads, myFavorites, myLikes, myCoins
        // Actions group at the bottom of the sidebar. Upload opens the
        // upload sheet (handled by a tap side-effect, never becomes the
        // active selection); Settings routes to SettingsView.
        case upload, settings

        var label: String {
            switch self {
            case .home:          "Home"
            case .discover:      "Discover"
            case .weekly:        "Weekly"
            case .collections:   "Collections"
            case .myUploads:     "My Uploads"
            case .myCollections: "My Collections"
            case .myDownloads:   "My Downloads"
            case .myFavorites:   "My Favorites"
            case .myLikes:       "My Likes"
            case .myCoins:       "My Coins"
            case .upload:        "Upload"
            case .settings:      "Settings"
            }
        }
        var icon: String {
            switch self {
            case .home:          "house"
            case .discover:      "sparkles"
            case .weekly:        "calendar.badge.clock"
            case .collections:   "rectangle.stack"
            case .myUploads:     "tray.and.arrow.up"
            case .myCollections: "rectangle.stack.badge.person.crop"
            case .myDownloads:   "arrow.down.circle"
            case .myFavorites:   "star"
            case .myLikes:       "heart"
            case .myCoins:       "circle.hexagongrid.fill"
            case .upload:        "square.and.arrow.up"
            case .settings:      "gearshape"
            }
        }
        var isMine: Bool {
            switch self {
            case .myUploads, .myCollections, .myDownloads, .myFavorites, .myLikes, .myCoins: true
            default: false
            }
        }
    }

    enum MainRoute: Hashable {
        case detail(slug: String, fallbackID: Int)
        case profile(username: String)
        case collection(slug: String, title: String)
        case device(slug: String, name: String)
        case search(query: String)
        case weeklyWeek(year: Int, week: Int)
        case category(id: Int, name: String, slug: String)
    }

    var body: some View {
        // Manual split layout (no NavigationSplitView) so the chrome is
        // fully deterministic and matches the reference mockup exactly:
        //   • A paper top bar across the window top — the native traffic
        //     lights float on it at their natural top-left position
        //     (we do NOT reposition them). Full-screen drops the buttons
        //     and the bar simply reads as a top margin.
        //   • A floating Liquid-Glass sidebar card: inset on left / top /
        //     bottom, rounded on all corners, hairline border, with a
        //     cool→warm vertical gradient fill.
        //   • A full-bleed detail surface reaching the window's right and
        //     bottom edges, rounded only on its top-leading corner.
        ZStack(alignment: .topLeading) {
            // Warm paper behind everything — shows as the top bar and the
            // thin gaps around the floating sidebar card.
            Color.paper.ignoresSafeArea()

            HStack(spacing: WindowChrome.inset) {
                MainSidebar(selection: $sidebar, collapsed: $sidebarCollapsed,
                            onUpload: { showingUpload = true })
                    .frame(width: sidebarCollapsed ? 64 : 240)
                    // Card visual lives in the BACKGROUND (not a clipShape)
                    // so the collapsed nav icons' hover tooltips can spill
                    // past the card's right edge without being clipped.
                    .background(
                        RoundedRectangle(cornerRadius: WindowChrome.radius, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.93, green: 0.95, blue: 0.97), Color.paper],
                                startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: WindowChrome.radius, style: .continuous)
                            .strokeBorder(Color.hair, lineWidth: 1)
                    )
                    .padding(.bottom, WindowChrome.inset)
                    // Draw above the detail pane so overflowing hover
                    // tooltips aren't covered by it.
                    .zIndex(1)
                    .animation(.easeInOut(duration: 0.22), value: sidebarCollapsed)

                detailPane
                    .clipShape(.rect(topLeadingRadius: WindowChrome.radius))
            }
            .padding(.leading, WindowChrome.inset)
            .padding(.top, WindowChrome.topBar)

            // Collapse toggle styled as a fourth traffic light. A
            // top-level ZStack child (not an .overlay) so it shares the
            // same ignoresSafeArea coordinate space and stays put in
            // full-screen. Positioned from the measured geometry of the
            // real buttons; full-screen (no lights) left-aligns it with
            // the sidebar card, same distance from the top as windowed.
            SidebarToggleButton(collapsed: sidebarCollapsed, size: metrics.trafficDotSize) {
                withAnimation(.easeInOut(duration: 0.22)) { sidebarCollapsed.toggle() }
            }
            .offset(x: metrics.isFullScreen ? WindowChrome.inset + 2 : metrics.trafficTrailingX + 18,
                    y: metrics.trafficCenterY - metrics.trafficDotSize / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.all)
        .background(Color.paper)
        .task { await auth.refreshProfile() }
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    // Detail surface: page-mesh palette tint behind every page (mirrors
    // the web's .d3-discover-mesh), the routed content, and the
    // navigation stack for full-page pushes.
    private var detailPane: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.paper
                PageMesh()
                ContentRouter(
                    sidebar: sidebar,
                    search: committedSearch,
                    onPick: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) },
                    onDevice: { d in path.append(.device(slug: d.slug, name: d.name)) },
                    onWeeklyWeek: { y, w in path.append(.weeklyWeek(year: y, week: w)) },
                    onCategory: { c in path.append(.category(id: c.id, name: c.name, slug: c.slug)) },
                    onUploader: { username in path.append(.profile(username: username)) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationDestination(for: MainRoute.self) { route in
                switch route {
                case .detail(let slug, _):
                    DetailPage(slug: slug,
                               onUploader: { path.append(.profile(username: $0)) },
                               onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .profile(let username):
                    ProfileView(username: username,
                                onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .collection(let slug, _):
                    CollectionDetailView(slug: slug,
                                         onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .device(let slug, let name):
                    DeviceDetailView(slug: slug, name: name,
                                     onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .search(let q):
                    SearchResultsView(query: q,
                                      onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .weeklyWeek(let y, let w):
                    WeeklyWeekView(year: y, week: w,
                                   onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .category(let id, let name, let slug):
                    CategoryFeedView(category: Category(id: id, name: name, slug: slug, sortOrder: nil),
                                     onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                }
            }
        }
        .onChange(of: sidebar) { _, _ in
            path.removeAll()
        }
    }

    private func commitSearch() {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            committedSearch = ""
        } else {
            committedSearch = q
            path.append(.search(query: q))
        }
    }
}

// Routes the sidebar selection to the appropriate top-level view.
struct ContentRouter: View {
    let sidebar: MainWindow.SidebarItem
    let search: String
    var onPick: (Wallpaper) -> Void
    var onDevice: (DeviceProfile) -> Void
    var onWeeklyWeek: (Int, Int) -> Void
    var onCategory: (Category) -> Void
    var onUploader: (String) -> Void

    var body: some View {
        switch sidebar {
        case .home:          HomeView(onPick: onPick, onOpenWeek: onWeeklyWeek)
        case .discover:      DiscoverView(search: search, onPick: onPick)
        case .weekly:        WeeklyArchiveView(onOpenWeek: onWeeklyWeek)
        case .collections:   CollectionsListView()
        case .myUploads:     MyLibraryGridView(kind: .uploads, onPick: onPick)
        case .myCollections: MyLibraryCollectionsView()
        case .myDownloads:   MyLibraryGridView(kind: .downloads, onPick: onPick)
        case .myFavorites:   MyLibraryGridView(kind: .favorites, onPick: onPick)
        case .myLikes:       MyLibraryGridView(kind: .likes, onPick: onPick)
        case .myCoins:       MyCoinsView()
        case .settings:      SettingsView(onOpenProfile: onUploader)
        // Upload never becomes the active selection — its sidebar row
        // opens the upload sheet via a tap side-effect. Render nothing.
        case .upload:        Color.clear
        }
    }
}
